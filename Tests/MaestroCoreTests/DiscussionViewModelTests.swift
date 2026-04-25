@testable import MaestroCore
import XCTest

@MainActor
final class DiscussionViewModelTests: XCTestCase {
    private let alice = AgentID(rawValue: "alice")
    private let bob = AgentID(rawValue: "bob")

    private func makeDiscussion(maxTurns: Int = 3) -> Discussion {
        Discussion(
            id: ThreadID.new(),
            title: "test",
            participants: [alice, bob],
            moderatorId: nil,
            maxTurns: maxTurns,
            state: .pending,
            turns: []
        )
    }

    private func makeEngine(
        discussion: Discussion,
        dispatcher: DiscussionDispatching = ScriptedDispatcher()
    ) -> DiscussionEngine {
        DiscussionEngine(
            discussion: discussion,
            moderator: RoundRobinModerator(),
            dispatcher: dispatcher,
            initialPrompt: "go"
        )
    }

    func testBindEventsCollectsEnvelopes() async throws {
        let discussion = makeDiscussion(maxTurns: 2)
        let engine = makeEngine(discussion: discussion)
        let viewModel = DiscussionViewModel(discussion: discussion, engine: engine)
        await viewModel.bindEvents()
        await viewModel.start()

        // 종료까지 대기 (RoundRobin + maxTurns=2 → 빠르게 완료)
        try await waitUntil(timeout: 2.0) { viewModel.state == .completed }

        XCTAssertEqual(viewModel.envelopes.count, 2)
        XCTAssertEqual(viewModel.envelopes.map(\.from), [alice, bob])
        XCTAssertEqual(viewModel.terminationReason, .maxTurnsReached)
    }

    func testCurrentSpeakerSetDuringDispatch() async throws {
        let dispatcher = SlowDispatcher(delayPerTurn: 0.3)
        let discussion = makeDiscussion(maxTurns: 5)
        let engine = makeEngine(discussion: discussion, dispatcher: dispatcher)
        let viewModel = DiscussionViewModel(discussion: discussion, engine: engine)
        await viewModel.bindEvents()
        await viewModel.start()

        try await waitUntil(timeout: 1.0) { viewModel.currentSpeaker != nil }
        XCTAssertNotNil(viewModel.currentSpeaker)
        await viewModel.terminate()
    }

    func testStateChangesPropagateToViewModel() async throws {
        let dispatcher = SlowDispatcher(delayPerTurn: 0.2)
        let discussion = makeDiscussion(maxTurns: 10)
        let engine = makeEngine(discussion: discussion, dispatcher: dispatcher)
        let viewModel = DiscussionViewModel(discussion: discussion, engine: engine)
        await viewModel.bindEvents()
        await viewModel.start()

        try await waitUntil(timeout: 1.0) { viewModel.state == .active }
        await viewModel.pause()
        try await waitUntil(timeout: 1.0) { viewModel.state == .paused }
        await viewModel.terminate()
        try await waitUntil(timeout: 1.0) { viewModel.state == .aborted }
    }

    func testTurnFailedPopulatesLastError() async throws {
        let discussion = makeDiscussion(maxTurns: 5)
        let engine = makeEngine(discussion: discussion, dispatcher: ThrowingDispatcher())
        let viewModel = DiscussionViewModel(discussion: discussion, engine: engine)
        await viewModel.bindEvents()
        await viewModel.start()

        try await waitUntil(timeout: 2.0) {
            viewModel.lastError != nil && viewModel.state == .aborted
        }
        XCTAssertNotNil(viewModel.lastError)
    }

    func testDismissErrorClears() async throws {
        // 진짜 에러 발생 후 dismiss 검증 (must-fix TEST-1)
        let discussion = makeDiscussion()
        let engine = makeEngine(discussion: discussion, dispatcher: ThrowingDispatcher())
        let viewModel = DiscussionViewModel(discussion: discussion, engine: engine)
        await viewModel.bindEvents()
        await viewModel.start()

        try await waitUntil(timeout: 2.0) { viewModel.lastError != nil }
        XCTAssertNotNil(viewModel.lastError, "ThrowingDispatcher 가 lastError 채웠어야")

        viewModel.dismissError()
        XCTAssertNil(viewModel.lastError)
    }

    private func waitUntil(
        timeout: TimeInterval,
        check: @escaping () -> Bool
    ) async throws {
        let start = Date()
        while !check() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("timeout waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

@MainActor
final class DiscussionStoreTests: XCTestCase {
    private let alice = AgentID(rawValue: "alice")
    private let bob = AgentID(rawValue: "bob")

    private func makeViewModel(state: DiscussionState = .pending) -> DiscussionViewModel {
        let discussion = Discussion(
            id: ThreadID.new(),
            title: "t",
            participants: [alice, bob],
            moderatorId: nil,
            maxTurns: 3,
            state: state,
            turns: []
        )
        let engine = DiscussionEngine(
            discussion: discussion,
            moderator: RoundRobinModerator(),
            dispatcher: ScriptedDispatcher(),
            initialPrompt: "go"
        )
        return DiscussionViewModel(discussion: discussion, engine: engine)
    }

    func testRegisterAddsViewModelInOrder() async {
        let store = DiscussionStore()
        let v1 = makeViewModel()
        let v2 = makeViewModel()
        await store.register(viewModel: v1)
        await store.register(viewModel: v2)
        XCTAssertEqual(store.orderedViewModels.count, 2)
        XCTAssertEqual(store.orderedViewModels[0].discussion.id, v1.discussion.id)
        XCTAssertEqual(store.orderedViewModels[1].discussion.id, v2.discussion.id)
    }

    func testRegisterIsIdempotentForSameID() async {
        let store = DiscussionStore()
        let v1 = makeViewModel()
        await store.register(viewModel: v1)
        await store.register(viewModel: v1)
        XCTAssertEqual(store.orderedViewModels.count, 1)
    }

    func testEvictRemovesViewModel() async {
        let store = DiscussionStore()
        let v1 = makeViewModel()
        await store.register(viewModel: v1)
        await store.evict(id: v1.discussion.id)
        XCTAssertNil(store.get(id: v1.discussion.id))
        XCTAssertTrue(store.orderedViewModels.isEmpty)
    }
}
