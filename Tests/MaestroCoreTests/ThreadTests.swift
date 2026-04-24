@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.4 — MessageThread 의 무결성 보장 + 트리 구조.
final class ThreadTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_714_500_000)

    func testNewThreadIsEmpty() {
        let thread = MessageThread(
            id: ThreadID(rawValue: "t-1"),
            parentId: nil,
            title: "Q3 보고",
            createdAt: fixedDate
        )
        XCTAssertTrue(thread.messages.isEmpty)
        XCTAssertNil(thread.parentId)
    }

    func testAppendAddsMatchingEnvelope() throws {
        var thread = MessageThread(
            id: ThreadID(rawValue: "t-1"),
            parentId: nil,
            title: "test",
            createdAt: fixedDate
        )
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            body: "hi",
            thread: ThreadID(rawValue: "t-1")
        )
        try thread.append(envelope)
        XCTAssertEqual(thread.messages.count, 1)
        XCTAssertEqual(thread.messages.first?.id, envelope.id)
    }

    func testAppendRejectsForeignThreadEnvelope() {
        var thread = MessageThread(
            id: ThreadID(rawValue: "t-1"),
            parentId: nil,
            title: "",
            createdAt: fixedDate
        )
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            body: "x",
            thread: ThreadID(rawValue: "t-other")
        )
        XCTAssertThrowsError(try thread.append(envelope)) { err in
            if case MessageThreadError.foreignEnvelope(let expected, let found) = err {
                XCTAssertEqual(expected.rawValue, "t-1")
                XCTAssertEqual(found.rawValue, "t-other")
            } else {
                XCTFail("예상과 다른 에러: \(err)")
            }
        }
    }

    func testChildThreadReferencesParent() {
        let parent = ThreadID(rawValue: "t-root")
        let child = MessageThread(
            id: ThreadID(rawValue: "t-child"),
            parentId: parent,
            title: "relay",
            createdAt: fixedDate
        )
        XCTAssertEqual(child.parentId, parent)
    }

    func testCodableRoundtrip() throws {
        var thread = MessageThread(
            id: ThreadID(rawValue: "t-1"),
            parentId: nil,
            title: "보고 스레드",
            createdAt: fixedDate
        )
        let envelope = MessageEnvelope(
            id: EnvelopeID(rawValue: "e-1"),
            threadId: ThreadID(rawValue: "t-1"),
            inReplyTo: nil,
            from: AgentID(rawValue: "a"),
            to: AgentID(rawValue: "b"),
            type: .task,
            body: "x",
            createdAt: fixedDate,
            expectReply: true
        )
        try thread.append(envelope)

        let data = try JSONEncoder.maestro.encode(thread)
        let decoded = try JSONDecoder.maestro.decode(MessageThread.self, from: data)
        XCTAssertEqual(decoded, thread)
    }
}
