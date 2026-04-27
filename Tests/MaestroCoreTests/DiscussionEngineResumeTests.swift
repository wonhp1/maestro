@testable import MaestroCore
import XCTest

/// v0.6.0 Phase 3 — DiscussionEngine.swapDispatcher / resume 단위 테스트.
final class DiscussionEngineResumeTests: XCTestCase {
    private let alice = AgentID(rawValue: "alice")
    private let bob = AgentID(rawValue: "bob")
    private let carol = AgentID(rawValue: "carol")

    private func makeDiscussion(
        maxTurns: Int = 10,
        state: DiscussionState = .pending,
        turns: [DiscussionTurn] = []
    ) -> Discussion {
        Discussion(
            id: ThreadID.new(),
            title: "test",
            participants: [alice, bob, carol],
            moderatorId: nil,
            maxTurns: maxTurns,
            state: state,
            turns: turns
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
            initialPrompt: "topic"
        )
    }

    /// 새 dispatcher 로 swap 자체는 state 영향 없음.
    func testSwapDispatcherPreservesState() async throws {
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 2)
        )
        await engine.swapDispatcher(ScriptedDispatcher())
        let state = await engine.discussion.state
        XCTAssertEqual(state, .pending)
    }

    /// completed → resume → 새 turn 발생 → 다시 completed.
    func testResumeFromCompletedAdvancesAgain() async throws {
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 1)
        )
        try await engine.start()
        await waitForTermination(engine)
        let pre = await engine.discussion
        XCTAssertEqual(pre.state, .completed)
        // resume + 1 턴 추가
        try await engine.resume(addingTurns: 1, with: ScriptedDispatcher())
        await waitForTermination(engine)
        let post = await engine.discussion
        XCTAssertEqual(post.maxTurns, 2)
        XCTAssertEqual(post.turns.count, 2, "resume 후 1턴 추가됨")
        XCTAssertEqual(post.state, .completed)
    }

    /// aborted 토론은 resume 거부.
    func testResumeFromAbortedThrowsCannotResume() async throws {
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 5)
        )
        try await engine.terminate(reason: DiscussionEngine.TerminationReason.userTerminated)
        do {
            try await engine.resume(addingTurns: 1, with: ScriptedDispatcher())
            XCTFail("aborted 에서 resume throws 해야")
        } catch let err as DiscussionError {
            if case .cannotResume = err {
                // OK
            } else {
                XCTFail("expected cannotResume, got \(err)")
            }
        }
    }

    private func waitForTermination(_ engine: DiscussionEngine) async {
        let stream = await engine.events()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in stream {
                    if case .terminated = event { break }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            await group.next()
            group.cancelAll()
        }
    }
}
