import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

// v0.9.0 Phase 3A-C — GeminiAdapter (skeleton + sendMessage + streaming).
final class GeminiAdapterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "gemini-test")
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
        XCTAssertEqual(detection.version, "0.40.0")
    }

    func testDetectReturnsNotInstalledWhenAbsent() async throws {
        let adapter = try makeAdapter(executableExists: false)
        let detection = await adapter.detect()
        XCTAssertFalse(detection.isInstalled)
    }

    // MARK: - createSession / destroy

    func testCreateSessionRegistersSession() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        XCTAssertEqual(session.adapterId.rawValue, "gemini")
        let active = await adapter.activeSessionIds()
        XCTAssertTrue(active.contains(session.id))
    }

    func testCreateSessionWithModelId() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(
            folderPath: tempDir,
            preferredSessionId: nil,
            modelId: "gemini-2.5-pro"
        )
        XCTAssertEqual(session.modelId, "gemini-2.5-pro")
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

    func testSendMessageReturnsAssistantText() async throws {
        let exec = ArgRecordingExec(stdout: geminiJSONL(text: "Hello there"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        let env = makeEnvelope(body: "hi")
        let response = try await adapter.sendMessage(env, in: session)
        XCTAssertEqual(response.body, "Hello there")
        XCTAssertEqual(response.from, env.to)
    }

    func testSendMessagePassesCorrectArgs() async throws {
        let exec = ArgRecordingExec(stdout: geminiJSONL(text: "ok"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(
            folderPath: tempDir, preferredSessionId: nil, modelId: "gemini-2.5-pro"
        )
        _ = try await adapter.sendMessage(makeEnvelope(body: "test prompt"), in: session)
        let calls = await exec.calls
        XCTAssertEqual(calls.count, 1)
        let args = calls[0]
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("test prompt"))
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("stream-json"))
        XCTAssertTrue(args.contains("--skip-trust"))
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("gemini-2.5-pro"))
    }

    func testSendMessageCapturesSessionIdAndModel() async throws {
        let exec = ArgRecordingExec(stdout: geminiJSONL(
            text: "ok", sessionId: "gem-sess-123", model: "gemini-3-flash-preview"
        ))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try await adapter.sendMessage(makeEnvelope(body: "hi"), in: session)
        let captured = await adapter.geminiSessionId(for: session.id)
        XCTAssertEqual(captured, "gem-sess-123")
        let model = await adapter.resolvedModel(for: session)
        XCTAssertEqual(model, "gemini-3-flash-preview")
    }

    func testSendMessageConcatenatesAssistantDeltas() async throws {
        // Gemini 의 delta 응답을 합쳐서 한 메시지로 반환
        let stdout = """
            {"type":"init","session_id":"x","model":"gemini-3-flash-preview"}
            {"type":"message","role":"user","content":"hi"}
            {"type":"message","role":"assistant","content":"Hello ","delta":true}
            {"type":"message","role":"assistant","content":"there.","delta":true}
            {"type":"result","status":"success","stats":{"total_tokens":10,"input_tokens":5,"output_tokens":3,"cached":0,"input":5,"duration_ms":100,"tool_calls":0,"models":{}}}
            """
        let exec = ArgRecordingExec(stdout: stdout)
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        let response = try await adapter.sendMessage(makeEnvelope(body: "hi"), in: session)
        XCTAssertEqual(response.body, "Hello there.")
    }

    func testSendMessageEnvIsSanitized() async throws {
        setenv("GEMINI_API_KEY", "leak-me", 1)
        defer { unsetenv("GEMINI_API_KEY") }
        let exec = ArgRecordingExec(stdout: geminiJSONL(text: "ok"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
        let envs = await exec.environments
        XCTAssertNil(envs[0]?["GEMINI_API_KEY"])
    }

    func testSendMessageThrowsOnError() async throws {
        let stdout = """
            {"type":"init","session_id":"x","model":"y"}
            {"type":"error","message":"quota exceeded"}
            """
        let exec = ArgRecordingExec(stdout: stdout)
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected error")
        } catch let err as GeminiResponseError {
            if case .geminiReportedError(let msg) = err {
                XCTAssertTrue(msg.contains("quota"))
            } else { XCTFail("wrong: \(err)") }
        }
    }

    func testSendMessageThrowsOnMalformedOutput() async throws {
        let exec = ArgRecordingExec(stdout: "not json at all")
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
            XCTFail("expected malformedOutput")
        } catch let err as GeminiResponseError {
            if case .malformedOutput = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    // MARK: - streamMessage

    func testStreamMessageEmitsTextChunks() async throws {
        let lines = [
            #"{"type":"init","session_id":"x","model":"gemini-3-flash-preview"}"#,
            #"{"type":"message","role":"user","content":"hi"}"#,
            #"{"type":"message","role":"assistant","content":"Hello ","delta":true}"#,
            #"{"type":"message","role":"assistant","content":"world","delta":true}"#,
            #"{"type":"result","status":"success"}"#,
        ]
        let streamer = ScriptedStreamerGem(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        var chunks: [ResponseChunk] = []
        for try await c in adapter.streamMessage(makeEnvelope(body: "hi"), in: session) {
            chunks.append(c)
        }
        let texts = chunks.filter { $0.kind == .text }.map(\.content)
        XCTAssertEqual(texts, ["Hello ", "world"])
        XCTAssertEqual(chunks.last?.kind, .completion)
    }

    func testStreamMessageThrowsOnError() async throws {
        let lines = [
            #"{"type":"init","session_id":"x","model":"y"}"#,
            #"{"type":"error","message":"401 Unauthorized"}"#,
        ]
        let streamer = ScriptedStreamerGem(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            for try await _ in adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
            XCTFail("expected throw")
        } catch let err as GeminiResponseError {
            if case .geminiReportedError = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testStreamMessageThrowsOnNonZeroExit() async throws {
        let streamer = ScriptedStreamerGem(
            stdoutLines: [], stderrLines: ["fatal error"], exitCode: 1
        )
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            for try await _ in adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
            XCTFail("expected processFailed")
        } catch let err as AdapterError {
            if case .processFailed = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testStreamMessageCapturesSessionFromInitEvent() async throws {
        let lines = [
            #"{"type":"init","session_id":"capture-me","model":"gemini-2.5-pro"}"#,
            #"{"type":"message","role":"assistant","content":"ok","delta":true}"#,
            #"{"type":"result","status":"success"}"#,
        ]
        let streamer = ScriptedStreamerGem(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        for try await _ in adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
        let captured = await adapter.geminiSessionId(for: session.id)
        XCTAssertEqual(captured, "capture-me")
        let model = await adapter.resolvedModel(for: session)
        XCTAssertEqual(model, "gemini-2.5-pro")
    }

    // MARK: - availableModels

    func testAvailableModelsContainsLatest() async throws {
        let adapter = try makeAdapter()
        let models = await adapter.availableModels()
        XCTAssertTrue(models.contains("gemini-3-flash-preview"))
        XCTAssertTrue(models.contains("gemini-2.5-pro"))
    }

    // MARK: - Helpers

    private func makeAdapter(
        executor: any ProcessExecuting = NullExec(),
        streamer: any ProcessStreaming = EmptyStreamerGem(),
        executableExists: Bool = true
    ) throws -> GeminiAdapter {
        let detector = CLIDetector(
            locator: GemTestLocator(
                url: executableExists ? URL(fileURLWithPath: "/usr/local/bin/gemini") : nil
            ),
            executor: GemDetectExec()
        )
        return try GeminiAdapter(executor: executor, streamer: streamer, detector: detector)
    }

    private func geminiJSONL(
        text: String,
        sessionId: String = "sess-default",
        model: String = "gemini-3-flash-preview"
    ) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
            {"type":"init","session_id":"\(sessionId)","model":"\(model)"}
            {"type":"message","role":"user","content":"prompt"}
            {"type":"message","role":"assistant","content":"\(escaped)","delta":true}
            {"type":"result","status":"success","stats":{}}
            """
    }

    private func makeEnvelope(body: String) -> MessageEnvelope {
        do {
            return MessageEnvelope.task(
                from: try AgentID.validated(rawValue: "user"),
                to: try AgentID.validated(rawValue: "gemini"),
                body: body
            )
        } catch {
            fatalError("\(error)")
        }
    }
}

// MARK: - Stubs

private struct GemTestLocator: ExecutableLocating {
    let url: URL?
    func locate(_ name: String) -> URL? { url }
}

private struct GemDetectExec: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        if arguments == ["--version"] {
            return ProcessOutput(stdout: "0.40.0\n", stderr: "", exitCode: 0)
        }
        return ProcessOutput(stdout: "", stderr: "", exitCode: 0)
    }
}

private struct NullExec: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        ProcessOutput(stdout: "", stderr: "", exitCode: 0)
    }
}

private actor ArgRecordingExec: ProcessExecuting {
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

private struct EmptyStreamerGem: ProcessStreaming {
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

private struct ScriptedStreamerGem: ProcessStreaming {
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
