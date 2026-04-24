@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.5 — Discussion 상태머신 + 턴 누적 + 봉투 검증.
final class DiscussionTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_714_500_000)

    private func makeDiscussion(
        id: ThreadID = ThreadID(rawValue: "d-1"),
        state: DiscussionState = .pending,
        maxTurns: Int = 10,
        turns: [DiscussionTurn] = []
    ) -> Discussion {
        Discussion(
            id: id,
            title: "Q3 전략",
            participants: [
                AgentID(rawValue: "cpo"),
                AgentID(rawValue: "cto"),
                AgentID(rawValue: "cmo"),
            ],
            moderatorId: AgentID(rawValue: "control"),
            maxTurns: maxTurns,
            state: state,
            turns: turns
        )
    }

    // MARK: Complete state transition matrix

    func testAllValidTransitions() throws {
        let validPairs: [(DiscussionState, DiscussionState)] = [
            (.pending, .active), (.pending, .aborted),
            (.active, .paused), (.active, .completed), (.active, .aborted),
            (.paused, .active), (.paused, .completed), (.paused, .aborted),
        ]
        for (from, to) in validPairs {
            var d = makeDiscussion(state: from)
            XCTAssertNoThrow(try d.transition(to: to), "허용되어야 함: \(from) → \(to)")
            XCTAssertEqual(d.state, to)
        }
    }

    func testAllInvalidTransitions() {
        let invalidPairs: [(DiscussionState, DiscussionState)] = [
            (.pending, .pending), (.pending, .paused), (.pending, .completed),
            (.active, .pending), (.active, .active),
            (.paused, .pending), (.paused, .paused),
            (.completed, .pending), (.completed, .active), (.completed, .paused),
            (.completed, .completed), (.completed, .aborted),
            (.aborted, .pending), (.aborted, .active), (.aborted, .paused),
            (.aborted, .completed), (.aborted, .aborted),
        ]
        for (from, to) in invalidPairs {
            var d = makeDiscussion(state: from)
            XCTAssertThrowsError(try d.transition(to: to), "거부되어야 함: \(from) → \(to)")
        }
    }

    // MARK: Turn recording with envelope

    func testRecordTurnFromMatchingEnvelope() throws {
        var d = makeDiscussion(state: .active)
        let env = MessageEnvelope(
            id: EnvelopeID(rawValue: "e-1"),
            threadId: d.id,
            inReplyTo: nil,
            from: AgentID(rawValue: "cpo"),
            to: AgentID(rawValue: "control"),
            type: .report,
            body: "...",
            createdAt: fixedDate,
            expectReply: false
        )
        try d.recordTurn(from: env)
        XCTAssertEqual(d.turns.count, 1)
        XCTAssertEqual(d.turns.first?.speaker, env.from)
        XCTAssertEqual(d.turns.first?.envelopeId, env.id)
    }

    func testRecordTurnRejectsForeignEnvelope() {
        var d = makeDiscussion(state: .active)
        let env = MessageEnvelope(
            id: EnvelopeID(rawValue: "e-1"),
            threadId: ThreadID(rawValue: "d-other"),
            inReplyTo: nil,
            from: AgentID(rawValue: "cpo"),
            to: AgentID(rawValue: "control"),
            type: .report,
            body: "...",
            createdAt: fixedDate,
            expectReply: false
        )
        XCTAssertThrowsError(try d.recordTurn(from: env)) { err in
            if case DiscussionError.foreignEnvelope(let expected, let found) = err {
                XCTAssertEqual(expected, d.id)
                XCTAssertEqual(found.rawValue, "d-other")
            } else {
                XCTFail("예상과 다른 에러: \(err)")
            }
        }
    }

    func testTurnIndexIsMonotonic() throws {
        var d = makeDiscussion(state: .active)
        try d.recordTurn(speaker: AgentID(rawValue: "cpo"), envelopeId: EnvelopeID.new(), at: fixedDate)
        try d.recordTurn(speaker: AgentID(rawValue: "cto"), envelopeId: EnvelopeID.new(), at: fixedDate)
        try d.recordTurn(speaker: AgentID(rawValue: "cmo"), envelopeId: EnvelopeID.new(), at: fixedDate)
        XCTAssertEqual(d.turns.map(\.turnIndex), [0, 1, 2])
    }

    func testTurnRejectedWhenNotActive() {
        for state in [DiscussionState.pending, .paused, .completed, .aborted] {
            var d = makeDiscussion(state: state)
            XCTAssertThrowsError(
                try d.recordTurn(
                    speaker: AgentID(rawValue: "cpo"),
                    envelopeId: EnvelopeID.new(),
                    at: fixedDate
                ),
                "\(state) 상태에선 거부"
            ) { err in
                XCTAssertEqual(err as? DiscussionError, .notActive(currentState: state))
            }
        }
    }

    func testTurnRejectedForNonParticipant() {
        var d = makeDiscussion(state: .active)
        let stranger = AgentID(rawValue: "stranger")
        XCTAssertThrowsError(
            try d.recordTurn(speaker: stranger, envelopeId: EnvelopeID.new(), at: fixedDate)
        ) { err in
            XCTAssertEqual(err as? DiscussionError, .notAParticipant(speaker: stranger))
        }
    }

    func testCompletesWhenMaxTurnsReached() throws {
        var d = makeDiscussion(state: .active, maxTurns: 2)
        try d.recordTurn(speaker: AgentID(rawValue: "cpo"), envelopeId: EnvelopeID.new(), at: fixedDate)
        XCTAssertEqual(d.state, .active, "1/2 턴 — 아직 active")
        try d.recordTurn(speaker: AgentID(rawValue: "cto"), envelopeId: EnvelopeID.new(), at: fixedDate)
        XCTAssertEqual(d.state, .completed, "2/2 턴 — 자동 완료")
    }

    func testRecordTurnAfterAutoCompletionIsRejected() throws {
        var d = makeDiscussion(state: .active, maxTurns: 1)
        try d.recordTurn(speaker: AgentID(rawValue: "cpo"), envelopeId: EnvelopeID.new(), at: fixedDate)
        XCTAssertEqual(d.state, .completed)
        // 추가 턴 시도 — .notActive 로 거부되어야.
        XCTAssertThrowsError(
            try d.recordTurn(speaker: AgentID(rawValue: "cto"), envelopeId: EnvelopeID.new(), at: fixedDate)
        ) { err in
            XCTAssertEqual(err as? DiscussionError, .notActive(currentState: .completed))
        }
    }

    // MARK: Codable

    func testCodableRoundtrip() throws {
        let original = makeDiscussion(state: .active)
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(Discussion.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDiscussionTurnCodable() throws {
        let turn = DiscussionTurn(
            turnIndex: 3,
            speaker: AgentID(rawValue: "cpo"),
            envelopeId: EnvelopeID(rawValue: "e-5"),
            timestamp: fixedDate
        )
        let data = try JSONEncoder.maestro.encode(turn)
        let decoded = try JSONDecoder.maestro.decode(DiscussionTurn.self, from: data)
        XCTAssertEqual(decoded, turn)
    }
}
