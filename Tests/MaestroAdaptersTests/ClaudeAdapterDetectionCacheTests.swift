import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// detect() 결과 캐싱 동작 검증 — Phase 7 perf must-fix.
/// 메인 ClaudeAdapterTests 의 길이 한도 분할.
final class ClaudeAdapterDetectionCacheTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "claude-cache")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testDetectResultCachedAcrossSendMessages() async throws {
        let detectExec = CountingDetectExecutor()
        let adapter = try makeAdapter(detectExec: detectExec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
        _ = try await adapter.sendMessage(makeEnvelope(body: "y"), in: session)
        let count = await detectExec.callCount
        XCTAssertEqual(count, 1, "detect 가 매 호출마다 spawn 됨")
    }

    func testInvalidateDetectionCacheReDetectsOnNextCall() async throws {
        let detectExec = CountingDetectExecutor()
        let adapter = try makeAdapter(detectExec: detectExec)
        let session = try await adapter.createSession(folderPath: tempDir)
        _ = try await adapter.sendMessage(makeEnvelope(body: "x"), in: session)
        await adapter.invalidateDetectionCache()
        _ = try await adapter.sendMessage(makeEnvelope(body: "y"), in: session)
        let count = await detectExec.callCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Helpers

    private func makeAdapter(detectExec: CountingDetectExecutor) throws -> ClaudeAdapter {
        let detector = CLIDetector(
            locator: FixedLocator(url: URL(fileURLWithPath: "/usr/local/bin/claude")),
            executor: detectExec
        )
        return try ClaudeAdapter(
            executor: ConstantSuccessExecutor(),
            streamer: EmptyStreamer(),
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
}

private struct FixedLocator: ExecutableLocating {
    let url: URL
    func locate(_ name: String) -> URL? { url }
}

private actor CountingDetectExecutor: ProcessExecuting {
    private(set) var callCount = 0
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        callCount += 1
        return ProcessOutput(stdout: "2.1.118 (Claude Code)\n", stderr: "", exitCode: 0)
    }
}

private struct ConstantSuccessExecutor: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        let raw = #"""
        {"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"x","stop_reason":"end_turn"}
        """#
        return ProcessOutput(stdout: raw, stderr: "", exitCode: 0)
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
