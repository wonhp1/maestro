import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// Phase 7 must-fix 결과 stream 모드 동작 검증.
final class ClaudeAdapterStreamTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "claude-stream")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testStreamArgsIncludeVerboseAndStreamJSON() async throws {
        let recorder = RecordingStreamerSpy()
        let adapter = try makeAdapter(streamer: recorder)
        let session = try await adapter.createSession(folderPath: tempDir)
        for try await _ in await adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].contains("--verbose"))
        XCTAssertTrue(calls[0].contains("stream-json"))
    }

    func testSendMessageArgsDoNotIncludeVerbose() async throws {
        let exec = OneShotExecutor(stdout: jsonResult(text: "ok"))
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
        let calls = await exec.argLog
        XCTAssertFalse(calls[0].contains("--verbose"))
        XCTAssertTrue(calls[0].contains("json"))
    }

    /// Phase 7 must-fix: stderr 라인이 chunk 로 yield 되지 않는지 검증.
    func testStderrLinesNotYieldedAsChunks() async throws {
        let streamer = ScriptedStreamerSpy(
            stdoutLines: [],
            stderrLines: ["warn: rate limit", "info: retry"],
            exitCode: 0
        )
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        var chunks: [ResponseChunk] = []
        for try await c in await adapter.streamMessage(makeEnvelope(body: "x"), in: session) {
            chunks.append(c)
        }
        XCTAssertTrue(chunks.isEmpty, "stderr 가 chunk 로 흘러나옴: \(chunks)")
    }

    /// Phase 7 must-fix: 비정상 종료 시 stderr 가 throw 의 메시지에 포함.
    func testNonZeroExitPropagatesStderr() async throws {
        let streamer = ScriptedStreamerSpy(
            stdoutLines: [],
            stderrLines: ["api auth failed", "exit 7"],
            exitCode: 7
        )
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        do {
            for try await _ in await adapter.streamMessage(makeEnvelope(body: "x"), in: session) {}
            XCTFail("expected processFailed")
        } catch let err as AdapterError {
            if case .processFailed(let code, let stderr) = err {
                XCTAssertEqual(code, 7)
                XCTAssertTrue(stderr.contains("api auth failed"))
            } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    /// Phase 7 must-fix: 첫 stdout 도착 시점에 initialized — cancel/break 후 다음 호출도 --resume.
    func testInitializedAtFirstStdoutNotAtStreamEnd() async throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"a"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"b"}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"a b"}"#,
        ]
        let streamer = ScriptedStreamerSpy(stdoutLines: lines, exitCode: 0)
        let adapter = try makeAdapter(streamer: streamer)
        let session = try await adapter.createSession(folderPath: tempDir)
        for try await _ in await adapter.streamMessage(makeEnvelope(body: "x"), in: session) {
            break
        }
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertTrue(initialized, "첫 stdout 후 initialized=true 여야 함")
    }

    func testNotInitializedOnClaudeReportedError() async throws {
        let raw = #"""
        {"type":"result","subtype":"error","is_error":true,"result":"auth required"}
        """#
        let exec = OneShotExecutor(stdout: raw)
        let adapter = try makeAdapter(executor: exec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try? await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertFalse(initialized)
    }

    // MARK: - Helpers

    private func makeAdapter(
        executor: any ProcessExecuting = OneShotExecutor(stdout: ""),
        streamer: any ProcessStreaming = ScriptedStreamerSpy(stdoutLines: [], exitCode: 0)
    ) throws -> ClaudeAdapter {
        let detector = CLIDetector(
            locator: ClaudeStreamFixedLocator(url: URL(fileURLWithPath: "/usr/local/bin/claude")),
            executor: ClaudeStreamDetectExecutor()
        )
        return try ClaudeAdapter(
            executor: executor,
            streamer: streamer,
            detector: detector,
            sanitizer: .default,
            userCommandsDirectory: tempDir
        )
    }

    private func makeEnvelope(body: String) -> MessageEnvelope {
        do {
            return MessageEnvelope.task(
                from: try AgentID.validated(rawValue: "user"),
                to: try AgentID.validated(rawValue: "claude"),
                body: body
            )
        } catch {
            fatalError("\(error)")
        }
    }

    private func jsonResult(text: String) -> String {
        #"""
        {"type":"result","subtype":"success","is_error":false,"result":"\#(text)","session_id":"x"}
        """#
    }
}

private struct ClaudeStreamFixedLocator: ExecutableLocating {
    let url: URL
    func locate(_ name: String) -> URL? { url }
}

private struct ClaudeStreamDetectExecutor: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        ProcessOutput(stdout: "2.1.118 (Claude Code)\n", stderr: "", exitCode: 0)
    }
}

private actor OneShotExecutor: ProcessExecuting {
    let stdout: String
    let exitCode: Int32
    private(set) var argLog: [[String]] = []

    init(stdout: String, exitCode: Int32 = 0) {
        self.stdout = stdout
        self.exitCode = exitCode
    }

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        argLog.append(arguments)
        return ProcessOutput(stdout: stdout, stderr: "", exitCode: exitCode)
    }
}

private struct ScriptedStreamerSpy: ProcessStreaming {
    let stdoutLines: [String]
    var stderrLines: [String] = []
    let exitCode: Int32

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

private actor RecordingStreamerSpy: ProcessStreaming {
    private(set) var calls: [[String]] = []

    nonisolated func stream(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessStreamEvent, Error> {
        let args = arguments
        return AsyncThrowingStream { continuation in
            Task {
                await self.append(args)
                continuation.yield(
                    ProcessStreamEvent(kind: .exited(exitCode: 0, reason: .exit))
                )
                continuation.finish()
            }
        }
    }

    private func append(_ args: [String]) { calls.append(args) }
}
