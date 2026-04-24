@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.5 — Discussion 상태머신 + 턴 누적.
final class DiscussionTests: XCTestCase {
    private func makeDiscussion(state: DiscussionState = .pending) -> Discussion {
        Discussion(
            id: ThreadID.new(),
            title: "Q3 전략",
            participants: [
                AgentID(rawValue: "cpo"),
                AgentID(rawValue: "cto"),
                AgentID(rawValue: "cmo"),
            ],
            moderatorId: AgentID(rawValue: "control"),
            maxTurns: 10,
            state: state,
            turns: []
        )
    }

    // MARK: State machine

    func testPendingToActiveOK() {
        var d = makeDiscussion(state: .pending)
        XCTAssertNoThrow(try d.transition(to: .active))
        XCTAssertEqual(d.state, .active)
    }

    func testActiveToPausedOK() {
        var d = makeDiscussion(state: .active)
        XCTAssertNoThrow(try d.transition(to: .paused))
    }

    func testPausedToActiveOK() {
        var d = makeDiscussion(state: .paused)
        XCTAssertNoThrow(try d.transition(to: .active))
    }

    func testCompletedIsTerminal() {
        var d = makeDiscussion(state: .completed)
        XCTAssertThrowsError(try d.transition(to: .active))
        XCTAssertThrowsError(try d.transition(to: .paused))
    }

    func testAbortedIsTerminal() {
        var d = makeDiscussion(state: .aborted)
        XCTAssertThrowsError(try d.transition(to: .active))
    }

    func testCannotGoBackToPending() {
        var d = makeDiscussion(state: .active)
        XCTAssertThrowsError(try d.transition(to: .pending))
    }

    // MARK: Turn accumulation

    func testTurnAddedMonotonically() {
        var d = makeDiscussion(state: .active)
        let env = MessageEnvelope(
            id: EnvelopeID.new(),
            threadId: d.id,
            inReplyTo: nil,
            from: AgentID(rawValue: "cpo"),
            to: AgentID(rawValue: "control"),
            type: .report,
            body: "...",
            createdAt: Date(),
            expectReply: false
        )
        XCTAssertNoThrow(try d.recordTurn(speaker: env.from, envelopeId: env.id, at: env.createdAt))
        XCTAssertEqual(d.turns.count, 1)
        XCTAssertEqual(d.turns.first?.turnIndex, 0)

        XCTAssertNoThrow(try d.recordTurn(speaker: AgentID(rawValue: "cto"), envelopeId: EnvelopeID.new(), at: Date()))
        XCTAssertEqual(d.turns.last?.turnIndex, 1)
    }

    func testTurnRejectedWhenNotActive() {
        var d = makeDiscussion(state: .paused)
        XCTAssertThrowsError(try d.recordTurn(
            speaker: AgentID(rawValue: "cpo"),
            envelopeId: EnvelopeID.new(),
            at: Date()
        ))
    }

    func testTurnRejectedForNonParticipant() {
        var d = makeDiscussion(state: .active)
        XCTAssertThrowsError(try d.recordTurn(
            speaker: AgentID(rawValue: "stranger"),
            envelopeId: EnvelopeID.new(),
            at: Date()
        ))
    }

    func testCompletesWhenMaxTurnsReached() {
        var d = Discussion(
            id: ThreadID.new(),
            title: "short",
            participants: [AgentID(rawValue: "a"), AgentID(rawValue: "b")],
            moderatorId: nil,
            maxTurns: 2,
            state: .active,
            turns: []
        )
        try? d.recordTurn(speaker: AgentID(rawValue: "a"), envelopeId: EnvelopeID.new(), at: Date())
        try? d.recordTurn(speaker: AgentID(rawValue: "b"), envelopeId: EnvelopeID.new(), at: Date())
        XCTAssertEqual(d.state, .completed, "maxTurns 도달 시 자동 완료")
    }

    // MARK: Codable

    func testCodableRoundtrip() throws {
        let original = makeDiscussion(state: .active)
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(Discussion.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
