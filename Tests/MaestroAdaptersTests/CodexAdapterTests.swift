import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// v0.9.0 Phase 2A — CodexAdapter skeleton 검증.
/// (Phase 2B 에서 sendMessage / streamMessage tests 추가 예정)
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
        XCTAssertTrue(models.contains("gpt-5"), "gpt-5 should be in available models")
        XCTAssertTrue(models.contains("o1-preview"), "o1-preview should be in available models")
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

    func testListSlashCommandsReturnsEmptyInPhase2A() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let cmds = await adapter.listSlashCommands(in: session)
        XCTAssertTrue(cmds.isEmpty)
    }

    func testCapturedSlashCommandsEmptyInitially() async throws {
        let adapter = try makeAdapter()
        let cmds = await adapter.capturedSlashCommands()
        XCTAssertTrue(cmds.isEmpty)
    }

    // MARK: - Helpers

    private func makeAdapter(
        executor: any ProcessExecuting = NullExecutor(),
        executableExists: Bool = true
    ) throws -> CodexAdapter {
        let detector = CLIDetector(
            locator: CodexTestLocator(
                url: executableExists ? URL(fileURLWithPath: "/usr/local/bin/codex") : nil
            ),
            executor: CodexDetectExecutor()
        )
        return try CodexAdapter(executor: executor, detector: detector)
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
