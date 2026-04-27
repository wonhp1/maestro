import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class ClaudeAdapterTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = try TestSupport.makeTempDirectory(named: "claude-home")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempHome)
        super.tearDown()
    }

    // MARK: - createSession / destroySession

    func testCreateSessionRegistersInActiveList() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempHome)
        let active = await adapter.activeSessionIds()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first, session.id)
        XCTAssertEqual(session.adapterId.rawValue, "claude")
        XCTAssertEqual(session.status, .active)
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertFalse(initialized, "첫 sendMessage 전에는 initialized=false")
    }

    func testDestroyUnknownSessionThrows() async throws {
        let adapter = try makeAdapter()
        let unknown = SessionID.new()
        do {
            try await adapter.destroySession(unknown)
            XCTFail("expected unknownSession")
        } catch let err as AdapterError {
            XCTAssertEqual(err, .unknownSession(id: unknown))
        }
    }

    // MARK: - sendMessage

    func testSendMessageFirstCallUsesSessionId() async throws {
        let exec = RecordingExecutor(stdout: jsonResultRaw(text: "hello"))
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        let env = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "user"),
            to: try AgentID.validated(rawValue: "claude"),
            body: "hi"
        )
        let response = try await adapter.sendMessage(env, in: session)
        XCTAssertEqual(response.body, "hello")
        let calls = await exec.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].arguments.contains("--session-id"))
        XCTAssertFalse(calls[0].arguments.contains("--resume"))
        XCTAssertTrue(calls[0].arguments.contains(session.id.rawValue))
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertTrue(initialized)
    }

    func testSendMessageSecondCallUsesResume() async throws {
        let exec = RecordingExecutor(stdout: jsonResultRaw(text: "ok"))
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        let env1 = makeTaskEnvelope(body: "first")
        let env2 = makeTaskEnvelope(body: "second")
        _ = try await adapter.sendMessage(env1, in: session)
        _ = try await adapter.sendMessage(env2, in: session)
        let calls = await exec.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[0].arguments.contains("--session-id"))
        XCTAssertTrue(calls[1].arguments.contains("--resume"))
        XCTAssertFalse(calls[1].arguments.contains("--session-id"))
    }

    func testSendMessageEnvIsSanitized() async throws {
        // adapter 가 sanitizer 통과 시키므로, 호출 env 에 시크릿 키가 없어야 함.
        // 부모에 fake key 셋팅 → adapter 통해 호출 → recorded env 에서 해당 키 없음 확인.
        setenv("ANTHROPIC_API_KEY", "should-not-leak", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        let exec = RecordingExecutor(stdout: jsonResultRaw(text: "ok"))
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        _ = try await adapter.sendMessage(makeTaskEnvelope(body: "x"), in: session)
        let calls = await exec.calls
        let env = calls[0].environment ?? [:]
        XCTAssertNil(env["ANTHROPIC_API_KEY"], "sanitizer 가 ANTHROPIC_API_KEY 통과시킴")
        XCTAssertNotNil(env["PATH"], "PATH 는 보존돼야")
    }

    func testSendMessageCwdMatchesSessionFolder() async throws {
        let exec = RecordingExecutor(stdout: jsonResultRaw(text: "ok"))
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        _ = try await adapter.sendMessage(makeTaskEnvelope(body: "x"), in: session)
        let calls = await exec.calls
        XCTAssertEqual(calls[0].cwd, tempHome)
    }

    func testSendMessageThrowsWhenClaudeReportsError() async throws {
        let raw = #"""
        {"type":"result","subtype":"error","is_error":true,"result":"auth required","session_id":"x"}
        """#
        let exec = RecordingExecutor(stdout: raw)
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        do {
            _ = try await adapter.sendMessage(makeTaskEnvelope(body: "x"), in: session)
            XCTFail("expected ClaudeResponseError")
        } catch ClaudeResponseError.claudeReportedError {
            // OK
        }
    }

    func testSendMessageThrowsWhenProcessExitsNonzero() async throws {
        let exec = RecordingExecutor(stdout: "", stderr: "boom", exitCode: 2)
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        do {
            _ = try await adapter.sendMessage(makeTaskEnvelope(body: "x"), in: session)
            XCTFail("expected processFailed")
        } catch let err as AdapterError {
            if case .processFailed = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testSendMessageThrowsWhenNotInstalled() async throws {
        let adapter = try makeAdapter(
            executor: RecordingExecutor(stdout: ""),
            executableExists: false
        )
        let session = try await adapter.createSession(folderPath: tempHome)
        do {
            _ = try await adapter.sendMessage(makeTaskEnvelope(body: "x"), in: session)
            XCTFail("expected notInstalled")
        } catch let err as AdapterError {
            XCTAssertEqual(err, .notInstalled(adapterId: "claude"))
        }
    }

    func testSendMessageThrowsWhenSessionUnknown() async throws {
        let adapter = try makeAdapter()
        let stranger = Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "x"),
            adapterId: try AdapterID.validated(rawValue: "claude"),
            folderPath: tempHome,
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
        do {
            _ = try await adapter.sendMessage(makeTaskEnvelope(body: "x"), in: stranger)
            XCTFail("expected unknownSession")
        } catch let err as AdapterError {
            if case .unknownSession = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    // MARK: - streamMessage

    func testStreamMessageEmitsTextThenCompletion() async throws {
        let lines = [
            #"{"type":"system","subtype":"init"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"hello","stop_reason":"end_turn"}"#,
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        let stream = await adapter.streamMessage(makeTaskEnvelope(body: "hi"), in: session)
        var collected: [ResponseChunk] = []
        for try await chunk in stream { collected.append(chunk) }
        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected[0].kind, .text)
        XCTAssertEqual(collected[0].content, "hello")
        XCTAssertEqual(collected[1].kind, .completion)
    }

    func testStreamMessageMarksSessionInitialized() async throws {
        let lines = [
            #"{"type":"result","subtype":"success","is_error":false,"result":""}"#,
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        for try await _ in await adapter.streamMessage(makeTaskEnvelope(body: "x"), in: session) {}
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertTrue(initialized)
    }

    func testStreamMessageThrowsOnNonZeroExit() async throws {
        let streamer = ScriptedStreamer(stdoutLines: [], exitCode: 7)
        let adapter = try makeAdapter(streamer: streamer, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        do {
            for try await _ in await adapter.streamMessage(makeTaskEnvelope(body: "x"), in: session) {}
            XCTFail("expected processFailed")
        } catch let err as AdapterError {
            if case .processFailed = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    // 추가 stream 검증 / detect cache 는 ClaudeAdapterStreamTests / ClaudeAdapterDetectionCacheTests 분리.

    // MARK: - listSlashCommands

    func testListSlashCommandsIncludesBuiltInsAndUserCommands() async throws {
        // tempHome 안에 .claude/commands/ + 사용자/프로젝트 명령 추가.
        let userDir = tempHome.appending(path: "userCmds", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try "Custom user command".write(
            to: userDir.appending(path: "myUser.md"),
            atomically: true, encoding: .utf8
        )

        let projectDir = tempHome.appending(path: ".claude/commands", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "Project-specific".write(
            to: projectDir.appending(path: "deploy.md"),
            atomically: true, encoding: .utf8
        )

        let adapter = try makeAdapter(userCommandsDirectory: userDir)
        let session = try await adapter.createSession(folderPath: tempHome)
        let cmds = await adapter.listSlashCommands(in: session)
        let names = Set(cmds.map(\.name))
        XCTAssertTrue(names.contains("clear"))      // built-in
        XCTAssertTrue(names.contains("myUser"))      // user
        XCTAssertTrue(names.contains("deploy"))      // project
        // category 분류 확인
        XCTAssertEqual(cmds.first(where: { $0.name == "myUser" })?.category, "user")
        XCTAssertEqual(cmds.first(where: { $0.name == "deploy" })?.category, "project")
    }

    // MARK: - v0.5.1 — modelId

    func testModelIdAddedAsModelFlag() async throws {
        let exec = RecordingExecutor(stdout: jsonResultRaw(text: "ok"))
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(
            folderPath: tempHome,
            preferredSessionId: nil,
            modelId: "claude-opus-4-1"
        )
        _ = try await adapter.sendMessage(makeTaskEnvelope(body: "hi"), in: session)
        let calls = await exec.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].arguments.contains("--model"))
        XCTAssertTrue(calls[0].arguments.contains("claude-opus-4-1"))
    }

    func testResolvedModelReturnsExplicitWhenSet() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(
            folderPath: tempHome,
            preferredSessionId: nil,
            modelId: "claude-opus-4-1"
        )
        let resolved = await adapter.resolvedModel(for: session)
        XCTAssertEqual(resolved, "claude-opus-4-1")
    }

    func testResolvedModelCapturesFromResponseWhenNotExplicit() async throws {
        let exec = RecordingExecutor(
            stdout: jsonResultRawWithModel(text: "ok", model: "claude-sonnet-4-5-20250929")
        )
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(folderPath: tempHome)
        // v0.5.5 — 응답 전엔 nil (정직). 옛 v0.5.3 의 knownDefaultModel fallback
        // 은 사용자 환경 실제 모델과 다를 수 있어 제거.
        let before = await adapter.resolvedModel(for: session)
        XCTAssertNil(before)
        _ = try await adapter.sendMessage(makeTaskEnvelope(body: "hi"), in: session)
        // 응답 후 lastSeen 으로 정정.
        let after = await adapter.resolvedModel(for: session)
        XCTAssertEqual(after, "claude-sonnet-4-5-20250929")
    }

    func testNilModelIdOmitsFlag() async throws {
        let exec = RecordingExecutor(stdout: jsonResultRaw(text: "ok"))
        let adapter = try makeAdapter(executor: exec, executableExists: true)
        let session = try await adapter.createSession(
            folderPath: tempHome,
            preferredSessionId: nil,
            modelId: nil
        )
        _ = try await adapter.sendMessage(makeTaskEnvelope(body: "hi"), in: session)
        let calls = await exec.calls
        XCTAssertFalse(calls[0].arguments.contains("--model"))
    }

    // MARK: - Static metadata

    func testStaticMetadata() {
        XCTAssertEqual(ClaudeAdapter.id, "claude")
        XCTAssertEqual(ClaudeAdapter.displayName, "Claude Code")
        XCTAssertFalse(ClaudeAdapter.iconName.isEmpty)
    }

    // MARK: - Helpers

    private func makeAdapter(
        executor: any ProcessExecuting = RecordingExecutor(stdout: ""),
        streamer: any ProcessStreaming = ScriptedStreamer(stdoutLines: [], exitCode: 0),
        executableExists: Bool = true,
        userCommandsDirectory: URL? = nil
    ) throws -> ClaudeAdapter {
        let detector = CLIDetector(
            locator: StubLocatorFixed(
                executable: executableExists ? URL(fileURLWithPath: "/usr/local/bin/claude") : nil
            ),
            executor: ScriptedDetectExecutor()
        )
        return try ClaudeAdapter(
            executor: executor,
            streamer: streamer,
            detector: detector,
            sanitizer: .default,
            userCommandsDirectory: userCommandsDirectory ?? tempHome
        )
    }

    private func makeTaskEnvelope(body: String) -> MessageEnvelope {
        do {
            return MessageEnvelope.task(
                from: try AgentID.validated(rawValue: "user"),
                to: try AgentID.validated(rawValue: "claude"),
                body: body
            )
        } catch {
            fatalError("envelope construction failed: \(error)")
        }
    }

    private func jsonResultRaw(text: String) -> String {
        #"""
        {"type":"result","subtype":"success","is_error":false,"result":"\#(text)","session_id":"abc","stop_reason":"end_turn"}
        """#
    }

    private func jsonResultRawWithModel(text: String, model: String) -> String {
        #"""
        {"type":"result","subtype":"success","is_error":false,"result":"\#(text)","session_id":"abc","stop_reason":"end_turn","model":"\#(model)"}
        """#
    }
}

// MARK: - Stubs

/// 호출 인자 / cwd / env 를 기록하고 동일 응답 반환.
private actor RecordingExecutor: ProcessExecuting {
    struct Call: Sendable {
        let executable: URL
        let arguments: [String]
        let cwd: URL?
        let environment: [String: String]?
    }

    private(set) var calls: [Call] = []
    let stdout: String
    let stderr: String
    let exitCode: Int32

    init(stdout: String, stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        calls.append(Call(
            executable: executable,
            arguments: arguments,
            cwd: currentDirectoryURL,
            environment: environment
        ))
        return ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

/// 미리 준비된 stdout/stderr 라인 + exit code 로 stream 발행.
private struct ScriptedStreamer: ProcessStreaming {
    let stdoutLines: [String]
    let stderrLines: [String]
    let exitCode: Int32

    init(stdoutLines: [String], stderrLines: [String] = [], exitCode: Int32 = 0) {
        self.stdoutLines = stdoutLines
        self.stderrLines = stderrLines
        self.exitCode = exitCode
    }

    func stream(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for line in stdoutLines {
                continuation.yield(ProcessStreamEvent(kind: .stdoutLine(line)))
            }
            for line in stderrLines {
                continuation.yield(ProcessStreamEvent(kind: .stderrLine(line)))
            }
            continuation.yield(
                ProcessStreamEvent(kind: .exited(exitCode: exitCode, reason: .exit))
            )
            continuation.finish()
        }
    }
}

/// 호출 인자 기록 — stdout/stderr 빈 채로 exit 0.
private actor RecordingStreamer: ProcessStreaming {
    struct Call: Sendable {
        let arguments: [String]
        let cwd: URL?
    }
    private(set) var calls: [Call] = []

    nonisolated func stream(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessStreamEvent, Error> {
        let args = arguments
        let cwd = currentDirectoryURL
        return AsyncThrowingStream { continuation in
            Task {
                await self.record(arguments: args, cwd: cwd)
                continuation.yield(
                    ProcessStreamEvent(kind: .exited(exitCode: 0, reason: .exit))
                )
                continuation.finish()
            }
        }
    }

    private func record(arguments: [String], cwd: URL?) {
        calls.append(Call(arguments: arguments, cwd: cwd))
    }
}

private struct StubLocatorFixed: ExecutableLocating {
    let executable: URL?
    func locate(_ executableName: String) -> URL? { executable }
}

/// detect 호출 시 valid version 응답 — adapter 의 detect path 에서만 사용.
private struct ScriptedDetectExecutor: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        ProcessOutput(stdout: "2.1.118 (Claude Code)\n", stderr: "", exitCode: 0)
    }
}

// CountingDetectExecutor 는 ClaudeAdapterDetectionCacheTests 로 분리됨.
