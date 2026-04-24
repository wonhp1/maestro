@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.1 — 에이전트 간 메시지의 봉투 계약.
final class MessageEnvelopeTests: XCTestCase {
    // 정수 초 — 부동소수점 드리프트 없이 roundtrip 가능 (Codable ms 정밀도 내).
    private let fixedDate = Date(timeIntervalSince1970: 1_714_500_000)

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
        XCTAssertTrue(envelope.expectReply)
        XCTAssertNil(envelope.inReplyTo)
        XCTAssertEqual(envelope.deliveryStatus, .pending)
        XCTAssertEqual(envelope.schemaVersion, MessageEnvelope.currentSchemaVersion)
        XCTAssertEqual(envelope.correlationId, envelope.id.rawValue, "기본 correlationId = id")
    }

    func testReportFactoryLinksToOriginal() {
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
        XCTAssertEqual(reply.threadId, original.threadId)
        XCTAssertEqual(reply.to, original.from)
        XCTAssertEqual(reply.from, original.to)
        XCTAssertEqual(reply.type, .report)
        XCTAssertFalse(reply.expectReply)
    }

    func testCorrelationIdExplicitOverride() {
        let env = MessageEnvelope(
            id: EnvelopeID(rawValue: "e-1"),
            threadId: ThreadID(rawValue: "t-1"),
            inReplyTo: nil,
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            type: .task,
            body: "x",
            createdAt: fixedDate,
            expectReply: true,
            correlationId: "retry-group-99"
        )
        XCTAssertEqual(env.correlationId, "retry-group-99")
    }

    // MARK: Copy-style mutators

    func testWithThreadIdPreservesOtherFields() {
        let env = MessageEnvelope.task(
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            body: "x"
        )
        let newThread = ThreadID(rawValue: "t-new")
        let copy = env.with(threadId: newThread)
        XCTAssertEqual(copy.threadId, newThread)
        XCTAssertEqual(copy.id, env.id)
        XCTAssertEqual(copy.body, env.body)
        XCTAssertEqual(copy.correlationId, env.correlationId)
        XCTAssertEqual(copy.deliveryStatus, env.deliveryStatus)
        XCTAssertEqual(copy.schemaVersion, env.schemaVersion)
    }

    func testWithDeliveryStatusTransition() {
        let env = MessageEnvelope.task(
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            body: "x"
        )
        let delivered = env.with(deliveryStatus: .delivered)
        XCTAssertEqual(delivered.deliveryStatus, .delivered)
        XCTAssertEqual(env.deliveryStatus, .pending, "원본은 불변")
    }

    // MARK: Codable

    func testJSONRoundtripWithFixedMsDate() throws {
        // ms 정밀도 고정 날짜 — iso8601 fractional seconds 저장과 정확히 일치.
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
        {"id":"e-1","threadId":"t-1","from":"a","type":"task","body":"x","createdAt":"2026-04-25T00:00:00Z","expectReply":true,"schemaVersion":1,"correlationId":"e-1","deliveryStatus":"pending"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(
            try JSONDecoder.maestro.decode(MessageEnvelope.self, from: brokenJSON),
            "`to` 필드 누락 시 거부"
        )
    }

    // MARK: Equality

    func testEqualityBasedOnAllFields() {
        let a = MessageEnvelope.task(
            from: AgentID(rawValue: "x"),
            to: AgentID(rawValue: "y"),
            body: "hi"
        )
        let bodyChanged = MessageEnvelope(
            id: a.id, threadId: a.threadId, inReplyTo: a.inReplyTo,
            from: a.from, to: a.to, type: a.type,
            body: "다른 본문",
            createdAt: a.createdAt,
            expectReply: a.expectReply,
            correlationId: a.correlationId,
            deliveryStatus: a.deliveryStatus,
            schemaVersion: a.schemaVersion
        )
        XCTAssertNotEqual(a, bodyChanged)
    }
}
