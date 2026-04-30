// swiftlint:disable file_length
import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

// v0.9.0 Phase 2A-C — CodexAdapter (skeleton + sendMessage + streaming).
// swiftlint:disable:next type_body_length
final class CodexAdapterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "codex-test")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    // MARK: - detect

    func testDetectReturnsInstalledWhenCLIPresent() async throws {
        let adapter = try makeAdapter(executableExists: true)
        let detection = await adapter.detect()
        XCTAssertTrue(detection.isInstalled)
        XCTAssertEqual(detection.version, "0.125.0")
    }

    func testDetectReturnsNotInstalledWhenAbsent() async throws {
        let adapter = try makeAdapter(executableExists: false)
        let detection = await adapter.detect()
        XCTAssertFalse(detection.isInstalled)
    }

    func testDetectCachesResultBetweenCalls() async throws {
        let counter = CountingDetector(version: "0.125.0")
        let adapter = try CodexAdapter(detector: await counter.makeDetector())
        _ = await adapter.detect()
        _ = await adapter.detect()
        _ = await adapter.detect()
        let calls = await counter.callCount
        XCTAssertEqual(calls, 1, "성공한 detect 는 1회만 실제 호출 (cache)")
    }

    func testInvalidateDetectionCacheForcesRecheck() async throws {
        let counter = CountingDetector(version: "0.125.0")
        let adapter = try CodexAdapter(detector: await counter.makeDetector())
        _ = await adapter.detect()
        await adapter.invalidateDetectionCache()
        _ = await adapter.detect()
        let calls = await counter.callCount
        XCTAssertEqual(calls, 2)
    }

    // MARK: - createSession

    func testCreateSessionRegistersSession() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        XCTAssertEqual(session.adapterId.rawValue, "codex")
        XCTAssertEqual(session.status, .active)
        let active = await adapter.activeSessionIds()
        XCTAssertEqual(active.count, 1)
        XCTAssertTrue(active.contains(session.id))
    }

    func testCreateSessionWithPreferredID() async throws {
        let adapter = try makeAdapter()
        let preferredID = SessionID.new()
        let session = try await adapter.createSession(
            folderPath: tempDir,
            preferredSessionId: preferredID,
            modelId: "gpt-5"
        )
        XCTAssertEqual(session.id, preferredID)
        XCTAssertEqual(session.modelId, "gpt-5")
    }

    func testCreateSessionResolvesSymlinks() async throws {
        let adapter = try makeAdapter()
        // tempDir 자체가 symlink 일 가능성 (macOS /var → /private/var)
        let session = try await adapter.createSession(folderPath: tempDir)
        // resolved 결과는 absolute path 여야 함
        XCTAssertTrue(session.folderPath.path.hasPrefix("/"))
    }

    // MARK: - destroySession

    func testDestroySessionRemovesFromActiveSet() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        try await adapter.destroySession(session.id)
        let active = await adapter.activeSessionIds()
        XCTAssertEqual(active.count, 0)
    }

    func testDestroyUnknownSessionThrows() async throws {
        let adapter = try makeAdapter()
        do {
            try await adapter.destroySession(SessionID.new())
            XCTFail("expected unknownSession")
        } catch let err as AdapterError {
            if case .unknownSession = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    // MARK: - availableModels / resolvedModel

    func testAvailableModelsReturnsKnownAliases() async throws {
        let adapter = try makeAdapter()
        let models = await adapter.availableModels()
        XCTAssertFalse(models.isEmpty)
        // models_cache.json 의 실제 카탈로그 기반 (2026-04 시점)
        XCTAssertTrue(models.contains("gpt-5.5"), "gpt-5.5 should be in available models")
        XCTAssertTrue(models.contains("gpt-5.3-codex"), "Codex 특화 모델 포함")
    }

    func testResolvedModelExplicitWhenSet() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(
            folderPath: tempDir, preferredSessionId: nil, modelId: "gpt-5-mini"
        )
        let resolved = await adapter.resolvedModel(for: session)
        XCTAssertEqual(resolved, "gpt-5-mini")
    }

    func testResolvedModelNilWhenNoExplicit() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let resolved = await adapter.resolvedModel(for: session)
        XCTAssertNil(resolved)
    }

    // MARK: - sendMessage (Phase 2B)

    func testSendMessageReturnsAgentMessageText() async throws {
        let exec = ArgRecordingExecutor(stdout: codexJSONL(text: "Hello there"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        let env = makeEnvelope(body: "hi")
        let response = try await adapter.sendMessage(env, in: session)
        XCTAssertEqual(response.body, "Hello there")
        XCTAssertEqual(response.inReplyTo, env.id)
        // 응답 envelope from/to 반전 확인
        XCTAssertEqual(response.from, env.to)
        XCTAssertEqual(response.to, env.from)
    }

    func testSendMessagePassesCorrectArgsForFirstCall() async throws {
        let exec = ArgRecordingExecutor(stdout: codexJSONL(text: "ok"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(
            folderPath: tempDir, preferredSessionId: nil, modelId: "gpt-5"
        )
        _ = try await adapter.sendMessage(makeEnvelope(body: "test prompt"), in: session)
        let calls = await exec.calls
        XCTAssertEqual(calls.count, 1)
        let args = calls[0]
        XCTAssertEqual(args.first, "exec", "subcommand 은 exec")
        XCTAssertFalse(args.contains("resume"), "첫 호출은 resume 아님")
        XCTAssertTrue(args.contains("test prompt"))
        XCTAssertTrue(args.contains("--json"))
        XCTAssertTrue(args.contains("--skip-git-repo-check"))
        // -C 사용 X — currentDirectoryURL 로 spawn 시 cwd 설정
        XCTAssertFalse(args.contains("-C"))
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("gpt-5"))
        // 첫 호출은 sandbox 명시
        XCTAssertTrue(args.contains("-s"))
        XCTAssertTrue(args.contains("workspace-write"))
    }

    func testSendMessageSecondCallUsesResumeWithThreadId() async throws {
        let firstStdout = codexJSONL(text: "first response", threadId: "tid-123")
        let exec = ArgRecordingExecutor(stdout: firstStdout)
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)

        // 첫 호출
        _ = try await adapter.sendMessage(makeEnvelope(body: "first"), in: session)
        let firstCallArgs = await exec.calls[0]
        XCTAssertFalse(firstCallArgs.contains("resume"))

        // 두 번째 호출 (thread_id 캡처됐으니 resume)
        _ = try await adapter.sendMessage(makeEnvelope(body: "second"), in: session)
        let secondCallArgs = await exec.calls[1]
        XCTAssertTrue(secondCallArgs.contains("resume"))
        XCTAssertTrue(secondCallArgs.contains("tid-123"))
        XCTAssertTrue(secondCallArgs.contains("second"))
    }

    func testSendMessageEnvIsSanitized() async throws {
        setenv("OPENAI_API_KEY", "leak-me", 1)
        defer { unsetenv("OPENAI_API_KEY") }
        let exec = ArgRecordingExecutor(stdout: codexJSONL(text: "ok"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
        let envs = await exec.environments
        XCTAssertNil(envs[0]?["OPENAI_API_KEY"], "secret leaked")
        XCTAssertNotNil(envs[0]?["PATH"])
    }

    func testSendMessageThrowsOnTurnFailedEvent() async throws {
        let stdout = """
        {"type":"thread.started","thread_id":"abc"}
        {"type":"turn.started"}
        {"type":"turn.failed","error":{"message":"401 Unauthorized"}}
        """
        let exec = ArgRecordingExecutor(stdout: stdout)
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected codexReportedError")
        } catch let err as CodexResponseError {
            if case .codexReportedError(let msg) = err {
                XCTAssertTrue(msg.contains("401"))
            } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testSendMessageThrowsOnMissingAgentMessage() async throws {
        let stdout = """
        {"type":"thread.started","thread_id":"abc"}
        {"type":"turn.started"}
        {"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}
        """
        let exec = ArgRecordingExecutor(stdout: stdout)
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected missingAgentMessage")
        } catch let err as CodexResponseError {
            if case .missingAgentMessage = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testSendMessageThrowsOnMalformedOutput() async throws {
        let exec = ArgRecordingExecutor(stdout: "not json at all")
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected malformedOutput")
        } catch let err as CodexResponseError {
            if case .malformedOutput = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testSendMessageStdoutCapEnforced() async throws {
        // 16MiB+ stdout 차단. Mock 으로 큰 출력 시뮬.
        let bigText = String(repeating: "A", count: 17 * 1024 * 1024)
        let exec = ArgRecordingExecutor(
            stdout: codexJSONL(text: bigText)  // valid JSONL 이지만 너무 큼
        )
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected processFailed")
        } catch let err as AdapterError {
            if case .processFailed = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testSendMessageCapturesThreadIdForResume() async throws {
        let exec = ArgRecordingExecutor(stdout: codexJSONL(text: "ok", threadId: "my-thread"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try await adapter.sendMessage(makeEnvelope(body: "hi"), in: session)
        let captured = await adapter.threadId(for: session.id)
        XCTAssertEqual(captured, "my-thread")
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertTrue(initialized)
    }

    // MARK: - streamMessage (Phase 2C)

    func testStreamMessageEmitsTextAndCompletion() async throws {
        let lines = [
            #"{"type":"thread.started","thread_id":"tid-stream"}"#,
            #"{"type":"turn.started"}"#,
            #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"hello world"}}"#,
            #"{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0}}"#,
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        var chunks: [ResponseChunk] = []
        for try await chunk in adapter.streamMessage(makeEnvelope(body: "hi"), in: session) {
            chunks.append(chunk)
        }
        let texts = chunks.filter { $0.kind == .text }.map(\.content)
        XCTAssertEqual(texts, ["hello world"])
        XCTAssertEqual(chunks.last?.kind, .completion)
        // thread_id 캡처
        let captured = await adapter.threadId(for: session.id)
        XCTAssertEqual(captured, "tid-stream")
    }

    func testStreamMessageEmitsToolUseAndResult() async throws {
        let lines = [
            #"{"type":"thread.started","thread_id":"tid-tool"}"#,
            #"{"type":"turn.started"}"#,
            #"{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"ls","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#,
            #"{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"ls","aggregated_output":"a.txt\nb.txt","exit_code":0,"status":"completed"}}"#,
            #"{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Found 2 files."}}"#,
            #"{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":3,"reasoning_output_tokens":0}}"#,
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        var chunks: [ResponseChunk] = []
        for try await chunk in adapter.streamMessage(makeEnvelope(body: "ls"), in: session) {
            chunks.append(chunk)
        }
        let kinds = chunks.map(\.kind)
        XCTAssertEqual(kinds, [.toolUse, .toolResult, .text, .completion])
        // tool_use 의 command 확인
        let toolUseContent = chunks.first(where: { $0.kind == .toolUse })?.content ?? ""
        XCTAssertTrue(toolUseContent.contains("\"command\":\"ls\""))
        XCTAssertTrue(toolUseContent.contains("\"status\":\"in_progress\""))
        // tool_result 의 output 확인
        let toolResultContent = chunks.first(where: { $0.kind == .toolResult })?.content ?? ""
        XCTAssertTrue(toolResultContent.contains("\"output\":\"a.txt\\nb.txt\""))
        XCTAssertTrue(toolResultContent.contains("\"exit_code\":0"))
    }

    func testStreamMessageThrowsOnTurnFailed() async throws {
        let lines = [
            #"{"type":"thread.started","thread_id":"x"}"#,
            #"{"type":"turn.started"}"#,
            #"{"type":"turn.failed","error":{"message":"401 Unauthorized"}}"#,
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            for try await _ in adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
            XCTFail("expected throw")
        } catch let err as CodexResponseError {
            if case .codexReportedError(let msg) = err {
                XCTAssertTrue(msg.contains("401"))
            } else { XCTFail("wrong: \(err)") }
        }
    }

    func testStreamMessageThrowsOnNonZeroExit() async throws {
        let streamer = ScriptedStreamer(
            stdoutLines: [],
            stderrLines: ["fatal: rate limit exceeded"],
            exitCode: 1
        )
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            for try await _ in adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
            XCTFail("expected processFailed")
        } catch let err as AdapterError {
            if case .processFailed(let code, let stderr) = err {
                XCTAssertEqual(code, 1)
                XCTAssertTrue(stderr.contains("rate limit"))
            } else { XCTFail("wrong: \(err)") }
        }
    }

    func testStreamMessageIgnoresNonJSONLines() async throws {
        let lines = [
            "Reading additional input from stdin...",  // 비-JSON
            #"{"type":"thread.started","thread_id":"x"}"#,
            "some random log line",
            #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"ok"}}"#,
            #"{"type":"turn.completed","usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}"#,
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        var chunks: [ResponseChunk] = []
        for try await chunk in adapter.streamMessage(makeEnvelope(body: "x"), in: session) {
            chunks.append(chunk)
        }
        let texts = chunks.filter { $0.kind == .text }.map(\.content)
        XCTAssertEqual(texts, ["ok"])
    }

    func testStreamMessageMarksSessionInitialized() async throws {
        let lines = [
            #"{"type":"thread.started","thread_id":"abc"}"#,
            #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"hi"}}"#,
            #"{"type":"turn.completed","usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}"#,
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        for try await _ in adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertTrue(initialized)
    }

    func testListSlashCommandsReturnsBuiltInsAndScans() async throws {
        // skills 디렉토리 비어있으면 builtin 만 — 최소 4개 (help/clear/model/login).
        let emptyDir = tempDir.appending(path: "empty-skills", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        let adapter = try makeAdapter(
            userSkillsDirectory: emptyDir, systemSkillsDirectory: emptyDir
        )
        let session = try await adapter.createSession(folderPath: tempDir)
        let cmds = await adapter.listSlashCommands(in: session)
        let names = cmds.map(\.name)
        XCTAssertTrue(names.contains("/help"))
        XCTAssertTrue(names.contains("/model"))
        XCTAssertGreaterThanOrEqual(cmds.count, 4)
    }

    func testListSlashCommandsScansSystemSkills() async throws {
        let userDir = tempDir.appending(path: "user-skills", directoryHint: .isDirectory)
        let systemDir = tempDir.appending(path: "system-skills", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemDir, withIntermediateDirectories: true)
        // system skill 1개
        let skill = systemDir.appending(path: "imagegen", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)

        let adapter = try makeAdapter(
            userSkillsDirectory: userDir, systemSkillsDirectory: systemDir
        )
        let session = try await adapter.createSession(folderPath: tempDir)
        let cmds = await adapter.listSlashCommands(in: session)
        XCTAssertTrue(cmds.contains { $0.name == "/imagegen" })
        XCTAssertTrue(cmds.contains { $0.name == "/imagegen" && $0.category == "system" })
    }

    func testAvailableModelsContainsLatest() async throws {
        let adapter = try makeAdapter()
        let models = await adapter.availableModels()
        XCTAssertTrue(models.contains("gpt-5.5"), "최신 GPT-5.5 모델 포함")
        XCTAssertTrue(models.contains("gpt-5.3-codex"), "Codex 특화 모델 포함")
    }

    func testCapturedSlashCommandsEmptyInitially() async throws {
        let adapter = try makeAdapter()
        let cmds = await adapter.capturedSlashCommands()
        XCTAssertTrue(cmds.isEmpty)
    }

    // MARK: - Helpers

    private func makeAdapter(
        executor: any ProcessExecuting = NullExecutor(),
        streamer: any ProcessStreaming = EmptyCodexStreamer(),
        executableExists: Bool = true,
        userSkillsDirectory: URL? = nil,
        systemSkillsDirectory: URL? = nil
    ) throws -> CodexAdapter {
        let detector = CLIDetector(
            locator: CodexTestLocator(
                url: executableExists ? URL(fileURLWithPath: "/usr/local/bin/codex") : nil
            ),
            executor: CodexDetectExecutor()
        )
        // skills 디렉토리 미주입 시 — 기본값 (`~/.codex/skills`) 사용. 사용자 실
        // 디렉토리가 테스트에 영향 줄 수 있어 가능하면 명시 권장.
        let defaults = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/skills", directoryHint: .isDirectory)
        return try CodexAdapter(
            executor: executor,
            streamer: streamer,
            detector: detector,
            userSkillsDirectory: userSkillsDirectory ?? defaults,
            systemSkillsDirectory: systemSkillsDirectory ?? defaults
                .appending(path: ".system", directoryHint: .isDirectory)
        )
    }

    /// 캡처된 실제 Codex stdout JSONL 모방.
    private func codexJSONL(text: String, threadId: String = "tid-default") -> String {
        """
        {"type":"thread.started","thread_id":"\(threadId)"}
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":\(jsonString(text))}}
        {"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":3,"reasoning_output_tokens":0}}
        """
    }

    private func jsonString(_ s: String) -> String {
        // 단순 escape — test 전용이라 known-safe input.
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private func makeEnvelope(body: String) -> MessageEnvelope {
        do {
            return MessageEnvelope.task(
                from: try AgentID.validated(rawValue: "user"),
                to: try AgentID.validated(rawValue: "codex"),
                body: body
            )
        } catch {
            fatalError("\(error)")
        }
    }
}

// MARK: - Stubs

private struct CodexTestLocator: ExecutableLocating {
    let url: URL?
    func locate(_ name: String) -> URL? { url }
}

private struct CodexDetectExecutor: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        // detect 와 sendMessage 둘 다 처리: --version 은 detect 용, 그 외는 빈 응답.
        if arguments == ["--version"] {
            return ProcessOutput(stdout: "codex-cli 0.125.0\n", stderr: "", exitCode: 0)
        }
        return ProcessOutput(stdout: "", stderr: "", exitCode: 0)
    }
}

private struct NullExecutor: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        ProcessOutput(stdout: "", stderr: "", exitCode: 0)
    }
}

private struct EmptyCodexStreamer: ProcessStreaming {
    func stream(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(ProcessStreamEvent(kind: .exited(exitCode: 0, reason: .exit)))
            continuation.finish()
        }
    }
}

private struct ScriptedStreamer: ProcessStreaming {
    let stdoutLines: [String]
    var stderrLines: [String] = []
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

private actor ArgRecordingExecutor: ProcessExecuting {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    private(set) var calls: [[String]] = []
    private(set) var environments: [[String: String]?] = []

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
        calls.append(arguments)
        environments.append(environment)
        return ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

/// detect() cache 검증용 — 호출 횟수 추적.
private actor CountingDetector {
    private(set) var callCount: Int = 0
    let version: String

    init(version: String) {
        self.version = version
    }

    /// CLIDetector 가 사용하는 executor 를 통해 호출 횟수 카운트.
    func makeDetector() -> CLIDetector {
        let counter = self
        return CLIDetector(
            locator: CodexTestLocator(url: URL(fileURLWithPath: "/usr/local/bin/codex")),
            executor: CountingExecutor(counter: counter, version: version)
        )
    }

    fileprivate func bump() async { callCount += 1 }
}

private struct CountingExecutor: ProcessExecuting {
    let counter: CountingDetector
    let version: String

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        await counter.bump()
        return ProcessOutput(stdout: "codex-cli \(version)\n", stderr: "", exitCode: 0)
    }
}
