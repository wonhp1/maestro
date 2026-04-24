@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.4 — Thread 의 트리 구조 + 메시지 누적.
final class ThreadTests: XCTestCase {
    func testNewThreadIsEmpty() {
        let thread = MessageThread(
            id: ThreadID.new(),
            parentId: nil,
            title: "Q3 보고",
            createdAt: Date()
        )
        XCTAssertTrue(thread.messages.isEmpty)
        XCTAssertNil(thread.parentId)
    }

    func testAppendingMessageAddsToEnd() {
        var thread = MessageThread(
            id: ThreadID.new(),
            parentId: nil,
            title: "test",
            createdAt: Date()
        )
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            body: "hi"
        )
        thread.append(envelope)
        XCTAssertEqual(thread.messages.count, 1)
        XCTAssertEqual(thread.messages.first?.id, envelope.id)
    }

    func testAppendRejectsForeignThreadMessage() {
        var thread = MessageThread(
            id: ThreadID(rawValue: "t-1"),
            parentId: nil,
            title: "",
            createdAt: Date()
        )
        // envelope.threadId 는 "t-1" 이 아닌 새 ThreadID — 들어오면 안 됨.
        var envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            body: "x"
        )
        envelope = envelope.with(threadId: ThreadID(rawValue: "t-other"))
        XCTAssertThrowsError(try thread.appendStrict(envelope))
    }

    func testChildThreadReferencesParent() {
        let parent = ThreadID(rawValue: "t-root")
        let child = MessageThread(
            id: ThreadID(rawValue: "t-child"),
            parentId: parent,
            title: "relay",
            createdAt: Date()
        )
        XCTAssertEqual(child.parentId, parent)
    }

    func testCodableRoundtrip() throws {
        var thread = MessageThread(
            id: ThreadID(rawValue: "t-1"),
            parentId: nil,
            title: "보고 스레드",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let envelope = MessageEnvelope(
            id: EnvelopeID(rawValue: "e-1"),
            threadId: ThreadID(rawValue: "t-1"),
            inReplyTo: nil,
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            type: .task,
            body: "x",
            createdAt: Date(timeIntervalSince1970: 0),
            expectReply: true
        )
        thread.append(envelope)

        let data = try JSONEncoder.maestro.encode(thread)
        let decoded = try JSONDecoder.maestro.decode(MessageThread.self, from: data)
        XCTAssertEqual(decoded, thread)
    }
}
