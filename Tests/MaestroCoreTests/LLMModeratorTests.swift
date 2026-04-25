@testable import MaestroCore
import XCTest

final class LLMModeratorTests: XCTestCase {
    private func makeDiscussion(participants: [String], moderator: String? = nil) -> Discussion {
        Discussion(
            id: ThreadID.new(),
            title: "test",
            participants: participants.map { AgentID(rawValue: $0) },
            moderatorId: moderator.map { AgentID(rawValue: $0) },
            maxTurns: 10,
            state: .active,
            turns: []
        )
    }

    private func makeEnvelope(from id: String, body: String) -> MessageEnvelope {
        MessageEnvelope.task(
            from: AgentID(rawValue: id),
            to: AgentID(rawValue: "control"),
            body: body
        )
    }

    func testParseNextTag() {
        let participants = [AgentID(rawValue: "alice"), AgentID(rawValue: "bob")]
        let result = LLMModerator.parseResponse("[NEXT: alice]", participants: participants)
        XCTAssertEqual(result, .next(AgentID(rawValue: "alice")))
    }

    func testParseConcludeReturnsConcludeCase() {
        let participants = [AgentID(rawValue: "alice")]
        let result = LLMModerator.parseResponse("[CONCLUDE]", participants: participants)
        XCTAssertEqual(result, .conclude)
    }

    func testParseRejectsUnknownAgent() {
        let participants = [AgentID(rawValue: "alice")]
        let result = LLMModerator.parseResponse("[NEXT: unknown]", participants: participants)
        XCTAssertEqual(result, .invalid, "참가자 목록에 없는 ID 는 invalid")
    }

    func testParseExtraTextIgnored() {
        let participants = [AgentID(rawValue: "alice")]
        let response = "조금 생각해본 결과 [NEXT: alice] 가 적절합니다."
        let result = LLMModerator.parseResponse(response, participants: participants)
        XCTAssertEqual(result, .next(AgentID(rawValue: "alice")))
    }

    func testParseGarbageReturnsInvalid() {
        let participants = [AgentID(rawValue: "alice")]
        let result = LLMModerator.parseResponse("뭔가 응답", participants: participants)
        XCTAssertEqual(result, .invalid)
    }

    func testNextSpeakerUsesQueryResponse() async {
        let moderator = LLMModerator(topic: "topic") { _ in
            "[NEXT: bob]"
        }
        let result = await moderator.nextSpeaker(
            in: makeDiscussion(participants: ["alice", "bob"])
        )
        XCTAssertEqual(result?.rawValue, "bob")
    }

    func testConcludeReturnsNilToTriggerEngineCompletion() async {
        let moderator = LLMModerator(topic: "topic") { _ in
            "[CONCLUDE]"
        }
        let result = await moderator.nextSpeaker(
            in: makeDiscussion(participants: ["alice", "bob"])
        )
        XCTAssertNil(result)
    }

    func testQueryFailureFallsBackToDefault() async {
        struct Boom: Error {}
        let moderator = LLMModerator(
            topic: "topic",
            query: { _ in throw Boom() },
            fallback: RoundRobinModerator()
        )
        let result = await moderator.nextSpeaker(
            in: makeDiscussion(participants: ["alice", "bob"])
        )
        // RoundRobin: 첫 발언자 alice 반환
        XCTAssertEqual(result?.rawValue, "alice")
    }

    func testObserveAccumulatesHistory() async {
        let moderator = LLMModerator(topic: "topic") { _ in "[CONCLUDE]" }
        await moderator.observe(envelope: makeEnvelope(from: "alice", body: "hello"))
        await moderator.observe(envelope: makeEnvelope(from: "bob", body: "world"))
        let history = await moderator.currentHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].body, "hello")
        XCTAssertEqual(history[1].speaker.rawValue, "bob")
    }

    func testHistoryShownInPromptToLLM() async {
        let receivedPrompts = Box()
        let moderator = LLMModerator(topic: "주제") { prompt in
            await receivedPrompts.set(prompt)
            return "[NEXT: alice]"
        }
        await moderator.observe(envelope: makeEnvelope(from: "alice", body: "first turn body"))
        _ = await moderator.nextSpeaker(in: makeDiscussion(participants: ["alice", "bob"]))
        let prompt = await receivedPrompts.get()
        XCTAssertTrue(prompt?.contains("first turn body") ?? false)
        XCTAssertTrue(prompt?.contains("주제") ?? false)
    }

    func testEmptyParticipantsReturnsNil() async {
        let moderator = LLMModerator(topic: "topic") { _ in "[NEXT: x]" }
        let result = await moderator.nextSpeaker(
            in: makeDiscussion(participants: [])
        )
        XCTAssertNil(result)
    }

    private actor Box {
        var value: String?
        func set(_ v: String?) { value = v }
        func get() -> String? { value }
    }
}
