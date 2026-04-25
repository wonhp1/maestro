@testable import MaestroCore
import XCTest

final class ChatMessageTests: XCTestCase {
    func testUserFactoryProducesCompleteStatus() {
        let msg = ChatMessage.user("hello")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "hello")
        XCTAssertEqual(msg.status, .complete)
    }

    func testAssistantPlaceholderEmptyStreaming() {
        let msg = ChatMessage.assistantPlaceholder()
        XCTAssertEqual(msg.role, .assistant)
        XCTAssertEqual(msg.content, "")
        XCTAssertEqual(msg.status, .streaming)
    }

    func testSystemFactory() {
        let msg = ChatMessage.system("connection lost")
        XCTAssertEqual(msg.role, .system)
        XCTAssertEqual(msg.status, .complete)
    }

    func testIDIsUnique() {
        let a = ChatMessage.user("a")
        let b = ChatMessage.user("b")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testStatusEqualityAcrossFailureMessages() {
        XCTAssertEqual(ChatMessage.Status.failed("x"), ChatMessage.Status.failed("x"))
        XCTAssertNotEqual(ChatMessage.Status.failed("x"), ChatMessage.Status.failed("y"))
        XCTAssertNotEqual(ChatMessage.Status.complete, ChatMessage.Status.streaming)
    }

    func testContentMutability() {
        var msg = ChatMessage.assistantPlaceholder()
        msg.content += "hello "
        msg.content += "world"
        XCTAssertEqual(msg.content, "hello world")
    }
}
