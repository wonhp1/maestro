@testable import MaestroCore
import XCTest

/// v0.5.0 Phase 4 — 결론 공유 (markShared + sharer protocol) 단위 테스트.
final class DiscussionShareTests: XCTestCase {
    private let alice = AgentID(rawValue: "alice")
    private let bob = AgentID(rawValue: "bob")
    private let carol = AgentID(rawValue: "carol")
    private let fixedDate = Date(timeIntervalSince1970: 1_714_500_000)

    private func makeEngine() -> DiscussionEngine {
        let discussion = Discussion(
            id: ThreadID.new(),
            title: "test",
            participants: [alice, bob, carol],
            moderatorId: nil,
            maxTurns: 1,
            state: .completed,
            turns: []
        )
        return DiscussionEngine(
            discussion: discussion,
            moderator: RoundRobinModerator(),
            dispatcher: ScriptedDispatcher(),
            initialPrompt: "topic"
        )
    }

    func testMarkSharedSetsFieldsAndBroadcasts() async throws {
        let engine = makeEngine()
        let stream = await engine.events()
        await engine.markShared(with: [alice, bob], at: fixedDate)
        let d = await engine.discussion
        XCTAssertEqual(d.sharedWith, [alice, bob])
        XCTAssertEqual(d.sharedAt, fixedDate)
        // event broadcast 확인
        let receiver = AgentListBox()
        let task = Task {
            for await event in stream {
                if case .sharedToTargets(let targets, _) = event {
                    await receiver.set(targets)
                    break
                }
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let got = await receiver.value
        XCTAssertEqual(got, [alice, bob])
    }

    func testSharerReceivesConclusionAndTargets() async throws {
        let sharer = RecordingSharer()
        let discussion = Discussion(
            id: ThreadID(rawValue: "d-1"),
            title: "Q3",
            participants: [alice, bob],
            moderatorId: nil,
            maxTurns: 1,
            state: .completed,
            turns: [],
            conclusion: "신규 시장 진입"
        )
        try await sharer.share(
            conclusion: "신규 시장 진입",
            discussion: discussion,
            with: [alice]
        )
        let calls = await sharer.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.conclusion, "신규 시장 진입")
        XCTAssertEqual(calls.first?.targets, [alice])
        XCTAssertEqual(calls.first?.discussionId.rawValue, "d-1")
    }
}

actor AgentListBox {
    private(set) var value: [AgentID] = []
    func set(_ list: [AgentID]) { value = list }
}

actor RecordingSharer: DiscussionConclusionSharing {
    struct Call: Sendable, Equatable {
        let conclusion: String
        let targets: [AgentID]
        let discussionId: ThreadID
    }
    private(set) var calls: [Call] = []

    func share(
        conclusion: String,
        discussion: Discussion,
        with targets: [AgentID]
    ) async throws {
        calls.append(
            Call(conclusion: conclusion, targets: targets, discussionId: discussion.id)
        )
    }
}
