@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.1 — 에이전트 간 메시지의 봉투 계약.
final class MessageEnvelopeTests: XCTestCase {
    // MARK: Construction

    func testTaskFactoryPopulatesRequiredFields() {
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "control"),
            to: AgentID(rawValue: "cpo"),
            body: "Q3 성과 보고해"
        )
        XCTAssertEqual(envelope.from.rawValue, "control")
        XCTAssertEqual(envelope.to.rawValue, "cpo")
        XCTAssertEqual(envelope.body, "Q3 성과 보고해")
        XCTAssertEqual(envelope.type, .task)
        XCTAssertTrue(envelope.expectReply, "task 기본값 expectReply=true")
        XCTAssertNil(envelope.inReplyTo)
    }

    func testReplyFactoryLinksToOriginal() {
        let original = MessageEnvelope.task(
            from: AgentID(rawValue: "control"),
            to: AgentID(rawValue: "cpo"),
            body: "보고해"
        )
        let reply = MessageEnvelope.report(
            from: AgentID(rawValue: "cpo"),
            inReplyTo: original,
            body: "Q3 매출 +23%"
        )
        XCTAssertEqual(reply.inReplyTo, original.id)
        XCTAssertEqual(reply.threadId, original.threadId, "같은 스레드에 귀속")
        XCTAssertEqual(reply.to, original.from, "응답은 원 발신자에게")
        XCTAssertEqual(reply.from, original.to)
        XCTAssertEqual(reply.type, .report)
        XCTAssertFalse(reply.expectReply, "report 기본값 expectReply=false")
    }

    func testExplicitInitAllowsCustomFields() {
        let now = Date()
        let envelope = MessageEnvelope(
            id: EnvelopeID(rawValue: "e-1"),
            threadId: ThreadID(rawValue: "t-1"),
            inReplyTo: EnvelopeID(rawValue: "e-0"),
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            type: .question,
            body: "왜?",
            createdAt: now,
            expectReply: true
        )
        XCTAssertEqual(envelope.id.rawValue, "e-1")
        XCTAssertEqual(envelope.createdAt, now)
    }

    // MARK: Codable

    func testJSONRoundtripPreservesAllFields() throws {
        // 고정 ms-정밀도 날짜 사용 — JSONCodecs 는 iso8601 fractional seconds (ms) 저장이라
        // `Date()` 의 μs 정밀도는 roundtrip 에서 ms 로 반올림됨. 이는 의도된 trade-off.
        let fixedDate = Date(timeIntervalSince1970: 1_714_500_000.123)
        let original = MessageEnvelope(
            id: EnvelopeID(rawValue: "e-1"),
            threadId: ThreadID(rawValue: "t-1"),
            inReplyTo: nil,
            from: AgentID(rawValue: "control"),
            to: AgentID(rawValue: "cpo"),
            type: .task,
            body: "한글 메시지 🎼",
            createdAt: fixedDate,
            expectReply: true
        )
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(MessageEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodingFailsForMissingRequiredField() {
        let brokenJSON = """
        {"id":"e-1","threadId":"t-1","from":"a","type":"task","body":"x","createdAt":"2026-04-25T00:00:00Z","expectReply":true}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder.maestro.decode(MessageEnvelope.self, from: brokenJSON))
    }

    // MARK: Hashable / Identity

    func testTwoEnvelopesWithSameIDHashEqually() {
        let id = EnvelopeID.new()
        let now = Date()
        let a = MessageEnvelope(
            id: id, threadId: ThreadID(rawValue: "t"), inReplyTo: nil,
            from: AgentID(rawValue: "x"), to: AgentID(rawValue: "y"),
            type: .fyi, body: "hi", createdAt: now, expectReply: false
        )
        let b = MessageEnvelope(
            id: id, threadId: ThreadID(rawValue: "t"), inReplyTo: nil,
            from: AgentID(rawValue: "x"), to: AgentID(rawValue: "y"),
            type: .fyi, body: "hi", createdAt: now, expectReply: false
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}
