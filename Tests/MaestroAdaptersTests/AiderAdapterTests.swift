import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class AiderAdapterTests: XCTestCase {
    private var tempDir: URL!
    private var historyRoot: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "aider-test")
        historyRoot = tempDir.appending(path: "history", directoryHint: .isDirectory)
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    // MARK: - createSession / destroySession

    func testCreateSessionRegistersAndCreatesHistoryPath() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let active = await adapter.activeSessionIds()
        XCTAssertEqual(active.count, 1)
        let historyPath = await adapter.chatHistoryPath(for: session.id)
        XCTAssertNotNil(historyPath)
        XCTAssertTrue(historyPath!.lastPathComponent.hasSuffix(".md"))
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

    // MARK: - sendMessage

    func testSendMessagePassesCorrectArgs() async throws {
        let exec = ArgRecordingExecutor(stdout: aiderStdout(answer: "ok"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        let env = makeEnvelope(body: "hi")
        let response = try await adapter.sendMessage(env, in: session)
        XCTAssertEqual(response.body, "ok")
        let calls = await exec.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].contains("--message"))
        XCTAssertTrue(calls[0].contains("hi"))
        XCTAssertTrue(calls[0].contains("--no-auto-commits"))
        XCTAssertTrue(calls[0].contains("--no-pretty"))
        XCTAssertTrue(calls[0].contains("--no-stream"))
        XCTAssertTrue(calls[0].contains("--yes-always"))
        XCTAssertTrue(calls[0].contains("--chat-history-file"))
    }

    func testSendMessageEnvIsSanitized() async throws {
        setenv("ANTHROPIC_API_KEY", "leak-me", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        let exec = ArgRecordingExecutor(stdout: aiderStdout(answer: "ok"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
        let envs = await exec.environments
        XCTAssertNil(envs[0]?["ANTHROPIC_API_KEY"], "secret leaked: \(String(describing: envs[0]))")
        XCTAssertNotNil(envs[0]?["PATH"])
    }

    func testSendMessageThrowsOnNonZeroExit() async throws {
        let exec = ArgRecordingExecutor(stdout: "", stderr: "boom", exitCode: 2)
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected processFailed")
        } catch let err as AdapterError {
            if case .processFailed = err { /* OK */ } else { XCTFail("wrong: \(err)") }
        }
    }

    func testSendMessageDetectsKnownAuthError() async throws {
        let raw = "litellm.exceptions.AuthenticationError: invalid api key\n"
        let exec = ArgRecordingExecutor(stdout: raw)
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected processFailed for known error")
        } catch let err as AdapterError {
            if case .processFailed(_, let stderr) = err {
                XCTAssertTrue(stderr.contains("aider error"))
            } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testSendMessageNotInstalledWhenLocatorMisses() async throws {
        let adapter = try makeAdapter(executableExists: false)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected notInstalled")
        } catch let err as AdapterError {
            XCTAssertEqual(err, .notInstalled(adapterId: "aider"))
        }
    }

    func testSendMessageUnknownSessionThrows() async throws {
        let adapter = try makeAdapter()
        let stranger = Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "x"),
            adapterId: try AdapterID.validated(rawValue: "aider"),
            folderPath: tempDir,
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: stranger)
            XCTFail("expected unknownSession")
        } catch let err as AdapterError {
            if case .unknownSession = err { /* OK */ } else { XCTFail("wrong: \(err)") }
        }
    }

    // MARK: - Concurrent session isolation (Phase 9 must-fix)

    func testConcurrentSessionsUseDistinctChatHistoryFiles() async throws {
        let exec = ArgRecordingExecutor(stdout: aiderStdout(answer: "ok"))
        let adapter = try makeAdapter(executor: exec)
        let session1 = try await adapter.createSession(folderPath: tempDir)
        let session2 = try await adapter.createSession(folderPath: tempDir)
        let path1 = await adapter.chatHistoryPath(for: session1.id)!
        let path2 = await adapter.chatHistoryPath(for: session2.id)!
        XCTAssertNotEqual(path1, path2, "두 세션이 같은 history 파일 공유")
        _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session1)
        _ = try await adapter.sendMessage(makeEnvelope(body: "y"), in: session2)
        let calls = await exec.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[0].contains(path1.path))
        XCTAssertTrue(calls[1].contains(path2.path))
    }

    // MARK: - Stream tests (Phase 9 must-fix)

    func testStreamMessageEmitsTextChunksAfterUserEcho() async throws {
        let lines = [
            "Aider v0.74.2",
            "Main model: claude-sonnet-4-5",
            "Git repo: .git with 3 files",
            "",
            "> prompt",
            "",
            "first body line",
            "second body line",
            "",
            "Tokens: 1k sent, 100 received",
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        var chunks: [ResponseChunk] = []
        for try await c in await adapter.streamMessage(makeEnvelope(body: "x"), in: session) {
            chunks.append(c)
        }
        let texts = chunks.compactMap { $0.kind == .text ? $0.content : nil }
        XCTAssertTrue(texts.contains("first body line"))
        XCTAssertTrue(texts.contains("second body line"))
        XCTAssertFalse(texts.contains { $0.contains("Aider v") })
        XCTAssertFalse(texts.contains { $0.contains("Tokens:") })
        XCTAssertEqual(chunks.last?.kind, .completion)
    }

    func testStreamMessageThrowsOnNonZeroExitWithStderr() async throws {
        let streamer = ScriptedStreamer(
            stdoutLines: [],
            stderrLines: ["fatal: rate limit exceeded", "exit"],
            exitCode: 1
        )
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            for try await _ in await adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
            XCTFail("expected processFailed")
        } catch let err as AdapterError {
            if case .processFailed(let code, let stderr) = err {
                XCTAssertEqual(code, 1)
                XCTAssertTrue(stderr.contains("rate limit"))
            } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    /// Phase 9 must-fix: `> ` echo 가 없어도 fallback 으로 본문 추출.
    func testStreamMessageFallbackEmitsBodyWhenNoUserEcho() async throws {
        // Aider 가 user echo 를 안 출력하는 가상 시나리오 — header 만 있고 본문은 fallback.
        let lines = [
            "Aider v0.74.2",
            "Main model: claude-sonnet-4-5",
            "Plain response without echo",
        ]
        let streamer = ScriptedStreamer(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        var texts: [String] = []
        for try await c in await adapter.streamMessage(makeEnvelope(body: "x"), in: session) {
            if case .text = c.kind { texts.append(c.content) }
        }
        let combined = texts.joined()
        XCTAssertTrue(combined.contains("Plain response without echo"))
    }

    // MARK: - listSlashCommands

    func testListSlashCommandsReturnsBuiltIns() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let cmds = await adapter.listSlashCommands(in: session)
        XCTAssertEqual(cmds.count, AiderSlashCommands.builtIns.count)
        XCTAssertTrue(cmds.contains { $0.name == "add" })
    }

    // MARK: - Static metadata

    func testStaticMetadata() {
        XCTAssertEqual(AiderAdapter.id, "aider")
        XCTAssertEqual(AiderAdapter.displayName, "Aider")
        XCTAssertFalse(AiderAdapter.iconName.isEmpty)
    }

    // MARK: - Helpers

    private func makeAdapter(
        executor: any ProcessExecuting = ArgRecordingExecutor(stdout: ""),
        streamer: any ProcessStreaming = EmptyStreamer(),
        executableExists: Bool = true
    ) throws -> AiderAdapter {
        let detector = CLIDetector(
            locator: AiderTestLocator(
                url: executableExists ? URL(fileURLWithPath: "/usr/local/bin/aider") : nil
            ),
            executor: AiderDetectExecutor()
        )
        return try AiderAdapter(
            executor: executor,
            streamer: streamer,
            detector: detector,
            sanitizer: .default,
            chatHistoryRoot: historyRoot
        )
    }

    private func makeEnvelope(body: String) -> MessageEnvelope {
        do {
            return MessageEnvelope.task(
                from: try AgentID.validated(rawValue: "user"),
                to: try AgentID.validated(rawValue: "aider"),
                body: body
            )
        } catch {
            fatalError("\(error)")
        }
    }

    private func aiderStdout(answer: String) -> String {
        """
        Aider v0.74.2
        Main model: claude-sonnet-4-5
        Git repo: .git

        > prompt

        \(answer)

        Tokens: 1k sent, 100 received. Cost: $0.01
        """
    }
}

// MARK: - Stubs

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

private struct AiderTestLocator: ExecutableLocating {
    let url: URL?
    func locate(_ name: String) -> URL? { url }
}

private struct AiderDetectExecutor: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        ProcessOutput(stdout: "aider 0.74.2\n", stderr: "", exitCode: 0)
    }
}

private struct EmptyStreamer: ProcessStreaming {
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
