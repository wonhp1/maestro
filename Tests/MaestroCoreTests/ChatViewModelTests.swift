import Foundation
@testable import MaestroCore
import XCTest

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testInitialStateEmpty() async throws {
        let (vm, _) = try await makeViewModel()
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertEqual(vm.draft, "")
        XCTAssertFalse(vm.isStreaming)
        XCTAssertNil(vm.lastError)
    }

    func testEmptyDraftSendIsNoOp() async throws {
        let (vm, _) = try await makeViewModel()
        vm.draft = "   \n\t  "
        vm.send()
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertFalse(vm.isStreaming)
    }

    func testSendAppendsUserAndAssistantPlaceholder() async throws {
        let (vm, adapter) = try await makeViewModel()
        // 응답 즉시 — text+completion.
        await adapter.scriptResponses([.text("hello"), .completion()])
        vm.draft = "hi"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[0].content, "hi")
        XCTAssertEqual(vm.messages[0].status, .complete)
        XCTAssertEqual(vm.messages[1].role, .assistant)
        XCTAssertEqual(vm.messages[1].content, "hello")
        XCTAssertEqual(vm.messages[1].status, .complete)
    }

    func testStreamingChunksAccumulateInPlaceholder() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptResponses([
            .text("Hel"),
            .text("lo, "),
            .text("world!"),
            .completion(),
        ])
        vm.draft = "hi"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        XCTAssertEqual(vm.messages.last?.content, "Hello, world!")
    }

    func testThinkingChunksDoNotPolluteContent() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptResponses([
            ResponseChunk(kind: .thinking, content: "internal reasoning"),
            .text("answer"),
            .completion(),
        ])
        vm.draft = "x"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        XCTAssertEqual(vm.messages.last?.content, "answer")
    }

    func testErrorChunkAppendedWithMarker() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptResponses([
            .text("partial"),
            ResponseChunk(kind: .error, content: "rate limited"),
            .completion(),
        ])
        vm.draft = "x"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        let last = vm.messages.last?.content ?? ""
        XCTAssertTrue(last.contains("partial"))
        XCTAssertTrue(last.contains("⚠️"))
        XCTAssertTrue(last.contains("rate limited"))
    }

    func testStreamErrorMarksMessageFailed() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptError(BoomError())
        vm.draft = "x"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        XCTAssertEqual(vm.messages.count, 2)
        if case .failed = vm.messages.last?.status {
            // OK
        } else {
            XCTFail("expected failed status, got \(String(describing: vm.messages.last?.status))")
        }
        XCTAssertNotNil(vm.lastError)
    }

    func testCancelMarksMessageCancelledAndDoesNotSurfaceError() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptResponses([.text("slow")], slowMillis: 200)
        vm.draft = "x"
        vm.send()
        try? await Task.sleep(nanoseconds: 50_000_000)
        vm.cancel()
        // cancel 은 동기적으로 isStreaming false 처리.
        XCTAssertFalse(vm.isStreaming)
        XCTAssertEqual(vm.messages.last?.status, .cancelled)
        XCTAssertNil(vm.lastError, "사용자 취소는 lastError 에 surface 안 됨")
    }

    /// Phase 8 must-fix: cancel 직후 즉시 send 가능해야.
    func testCancelThenImmediateSendStartsNewStream() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptResponses([.text("slow")], slowMillis: 200)
        vm.draft = "first"
        vm.send()
        try? await Task.sleep(nanoseconds: 50_000_000)
        vm.cancel()
        XCTAssertFalse(vm.isStreaming)
        // 즉시 두 번째 send.
        await adapter.scriptResponses([.text("second-resp"), .completion()])
        vm.draft = "second"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        // 첫 user + 첫 cancelled placeholder + 두번째 user + 두번째 assistant = 4
        XCTAssertEqual(vm.messages.count, 4)
        XCTAssertEqual(vm.messages[2].role, .user)
        XCTAssertEqual(vm.messages[2].content, "second")
        XCTAssertEqual(vm.messages[3].content, "second-resp")
        XCTAssertEqual(vm.messages[3].status, .complete)
    }

    func testConcurrentSendBlockedWhileStreaming() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptResponses([.text("slow")], slowMillis: 200)
        vm.draft = "first"
        vm.send()
        XCTAssertTrue(vm.isStreaming)
        // 두 번째 send — draft 가 비어있어도 첫 send 이후 isStreaming=true 라 reject.
        vm.draft = "second"
        vm.send()
        XCTAssertEqual(vm.messages.count, 2, "두 번째 send 가 messages 에 추가됨")
        try await waitForCondition { !vm.isStreaming }
    }

    /// Phase 8 must-fix: thinking/toolUse/toolResult 는 chat content 에 영향 없음.
    func testToolUseAndToolResultChunksAreSilentlyDropped() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptResponses([
            .text("a"),
            ResponseChunk(kind: .toolUse, content: #"{"name":"Read"}"#),
            ResponseChunk(kind: .toolResult, content: "file content"),
            .text("b"),
            .completion(),
        ])
        vm.draft = "x"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        XCTAssertEqual(vm.messages.last?.content, "ab")
    }

    /// Phase 8 sec must-fix: content cap 초과 시 truncation marker 부착.
    func testContentExceedingCapTruncates() async throws {
        let (vm, adapter) = try await makeViewModel()
        // cap 초과를 빠르게 트리거하기 위해 매우 큰 단일 chunk.
        let big = String(repeating: "x", count: ChatViewModel.maxMessageContentBytes + 1000)
        await adapter.scriptResponses([.text(big), .completion()])
        vm.draft = "x"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        let last = vm.messages.last?.content ?? ""
        XCTAssertLessThanOrEqual(last.utf8.count, ChatViewModel.maxMessageContentBytes + 100)
        XCTAssertTrue(last.contains("[…출력이 한도를 초과해 잘림]"))
    }

    func testClearLastErrorResetsField() async throws {
        let (vm, adapter) = try await makeViewModel()
        await adapter.scriptError(BoomError())
        vm.draft = "x"
        vm.send()
        try await waitForCondition { !vm.isStreaming }
        XCTAssertNotNil(vm.lastError)
        vm.clearLastError()
        XCTAssertNil(vm.lastError)
    }

    // MARK: - Helpers

    private func makeViewModel() async throws -> (ChatViewModel, ScriptedAdapter) {
        let adapter = ScriptedAdapter()
        let session = try await adapter.createSession(
            folderPath: URL(fileURLWithPath: "/tmp")
        )
        let vm = try ChatViewModel(adapter: adapter, session: session)
        return (vm, adapter)
    }

    private func waitForCondition(
        timeout: TimeInterval = 2,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() > deadline {
                throw WaitTimeoutError()
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

private struct BoomError: Error {}
private struct WaitTimeoutError: Error {}

/// 테스트용 어댑터 — script 된 chunks 를 yield. AgentAdapter conformance.
private actor ScriptedAdapter: AgentAdapter {
    static let id = "scripted"
    static let displayName = "Scripted"

    private var sessions: [SessionID: Session] = [:]
    private var scriptedChunks: [ResponseChunk] = []
    private var scriptedError: Error?
    private var slowMillis: UInt64 = 0

    func scriptResponses(_ chunks: [ResponseChunk], slowMillis: Int = 0) {
        self.scriptedChunks = chunks
        self.scriptedError = nil
        self.slowMillis = UInt64(slowMillis)
    }

    func scriptError(_ error: Error) {
        self.scriptedChunks = []
        self.scriptedError = error
        self.slowMillis = 0
    }

    func detect() async -> AdapterDetection { .notInstalled() }

    func createSession(folderPath: URL) async throws -> Session {
        let session = Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "scripted"),
            adapterId: try AdapterID.validated(rawValue: "scripted"),
            folderPath: folderPath,
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
        sessions[session.id] = session
        return session
    }

    func destroySession(_ id: SessionID) async throws {
        sessions.removeValue(forKey: id)
    }

    func sendMessage(
        _ envelope: MessageEnvelope, in session: Session
    ) async throws -> MessageEnvelope {
        if let scriptedError { throw scriptedError }
        let body = scriptedChunks
            .compactMap { if case .text = $0.kind { return $0.content } else { return nil } }
            .joined()
        return MessageEnvelope.report(from: envelope.to, inReplyTo: envelope, body: body)
    }

    nonisolated func streamMessage(
        _ envelope: MessageEnvelope, in session: Session
    ) -> AsyncThrowingStream<ResponseChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                let snapshot = await self.snapshot()
                if let error = snapshot.error {
                    continuation.finish(throwing: error)
                    return
                }
                for chunk in snapshot.chunks {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    if snapshot.slow > 0 {
                        try? await Task.sleep(nanoseconds: snapshot.slow * 1_000_000)
                    }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct Snapshot: Sendable {
        let chunks: [ResponseChunk]
        let error: Error?
        let slow: UInt64
    }

    private func snapshot() -> Snapshot {
        Snapshot(chunks: scriptedChunks, error: scriptedError, slow: slowMillis)
    }
}
