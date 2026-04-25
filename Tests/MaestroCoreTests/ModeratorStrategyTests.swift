@testable import MaestroCore
import XCTest

final class ModeratorStrategyTests: XCTestCase {
    private let alice = AgentID(rawValue: "alice")
    private let bob = AgentID(rawValue: "bob")
    private let carol = AgentID(rawValue: "carol")

    private func makeDiscussion(
        participants: [AgentID],
        moderator: AgentID? = nil,
        turns: [DiscussionTurn] = []
    ) -> Discussion {
        Discussion(
            id: ThreadID.new(),
            title: "test",
            participants: participants,
            moderatorId: moderator,
            maxTurns: 100,
            state: .active,
            turns: turns
        )
    }

    private func makeTurn(speaker: AgentID, index: Int) -> DiscussionTurn {
        DiscussionTurn(
            turnIndex: index, speaker: speaker,
            envelopeId: EnvelopeID.new(), timestamp: Date()
        )
    }

    // MARK: - RoundRobin

    func testRoundRobinFirstSpeakerIsFirstParticipant() async {
        let strategy = RoundRobinModerator()
        let discussion = makeDiscussion(participants: [alice, bob, carol])
        let next = await strategy.nextSpeaker(in: discussion)
        XCTAssertEqual(next, alice)
    }

    func testRoundRobinAdvancesAfterEachTurn() async {
        let strategy = RoundRobinModerator()
        let d1 = makeDiscussion(
            participants: [alice, bob, carol],
            turns: [makeTurn(speaker: alice, index: 0)]
        )
        let next1 = await strategy.nextSpeaker(in: d1)
        XCTAssertEqual(next1, bob)

        let d2 = makeDiscussion(
            participants: [alice, bob, carol],
            turns: [makeTurn(speaker: alice, index: 0), makeTurn(speaker: bob, index: 1)]
        )
        let next2 = await strategy.nextSpeaker(in: d2)
        XCTAssertEqual(next2, carol)
    }

    func testRoundRobinWrapsAroundToFirst() async {
        let strategy = RoundRobinModerator()
        let d = makeDiscussion(
            participants: [alice, bob],
            turns: [makeTurn(speaker: bob, index: 0)]
        )
        let next = await strategy.nextSpeaker(in: d)
        XCTAssertEqual(next, alice)
    }

    func testRoundRobinSkipsModerator() async {
        let strategy = RoundRobinModerator()
        let d = makeDiscussion(participants: [alice, bob, carol], moderator: bob)
        let next = await strategy.nextSpeaker(in: d)
        XCTAssertNotEqual(next, bob)
        XCTAssertTrue([alice, carol].contains(next))
    }

    // MARK: - Random

    func testRandomReturnsParticipant() async {
        let strategy = RandomModerator()
        let d = makeDiscussion(participants: [alice, bob, carol])
        for _ in 0..<10 {
            let next = await strategy.nextSpeaker(in: d)
            XCTAssertTrue(d.participants.contains(next!))
        }
    }

    func testRandomSkipsModerator() async {
        let strategy = RandomModerator()
        let d = makeDiscussion(participants: [alice, bob, carol], moderator: alice)
        for _ in 0..<10 {
            let next = await strategy.nextSpeaker(in: d)
            XCTAssertNotEqual(next, alice)
        }
    }

    // MARK: - Scripted

    func testScriptedFollowsScheduleThenReturnsNil() async {
        let strategy = ScriptedModerator(schedule: [alice, bob])
        let d = makeDiscussion(participants: [alice, bob, carol])
        let n1 = await strategy.nextSpeaker(in: d)
        let n2 = await strategy.nextSpeaker(in: d)
        let n3 = await strategy.nextSpeaker(in: d)
        XCTAssertEqual(n1, alice)
        XCTAssertEqual(n2, bob)
        XCTAssertNil(n3)
    }
}
