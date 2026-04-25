@testable import MaestroCore
import XCTest

@MainActor
final class DiscussionStoreSelectionTests: XCTestCase {
    func testRegisterAddsToOrderedListAndActiveCount() async {
        let store = DiscussionStore()
        let viewModel = makeViewModel(state: .active)
        await store.register(viewModel: viewModel)
        XCTAssertEqual(store.orderedViewModels.count, 1)
        XCTAssertEqual(store.activeViewModels.count, 1)
        XCTAssertEqual(store.orderedViewModels.first?.discussion.id, viewModel.discussion.id)
    }

    func testCompletedDiscussionSeparatedFromActive() async {
        let store = DiscussionStore()
        let active = makeViewModel(state: .active)
        let completed = makeViewModel(state: .completed)
        await store.register(viewModel: active)
        await store.register(viewModel: completed)
        XCTAssertEqual(store.orderedViewModels.count, 2)
        XCTAssertEqual(store.activeViewModels.count, 1)
        XCTAssertEqual(store.activeViewModels.first?.discussion.id, active.discussion.id)
    }

    func testEvictRemovesFromBothListAndActive() async {
        let store = DiscussionStore()
        let viewModel = makeViewModel(state: .active)
        await store.register(viewModel: viewModel)
        await store.evict(id: viewModel.discussion.id)
        XCTAssertTrue(store.orderedViewModels.isEmpty)
        XCTAssertTrue(store.activeViewModels.isEmpty)
    }

    private func makeViewModel(state: DiscussionState) -> DiscussionViewModel {
        let discussion = Discussion(
            id: ThreadID.new(),
            title: "테스트 토론",
            participants: [
                AgentID(rawValue: "a"),
                AgentID(rawValue: "b"),
            ],
            moderatorId: nil,
            maxTurns: 10,
            state: state,
            turns: []
        )
        let dispatcher = NoopDispatcher()
        let engine = DiscussionEngine(
            discussion: discussion,
            moderator: RoundRobinModerator(),
            dispatcher: dispatcher,
            initialPrompt: "go"
        )
        return DiscussionViewModel(discussion: discussion, engine: engine)
    }
}

private struct NoopDispatcher: DiscussionDispatching {
    func dispatchTurn(
        discussion: Discussion,
        speaker: AgentID,
        prompt: String
    ) async throws -> MessageEnvelope {
        throw DiscussionEngineError.noReply(speaker: speaker)
    }
}
