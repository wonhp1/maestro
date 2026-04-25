import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class ClaudeStreamParserTests: XCTestCase {
    func testAssistantTextLineYieldsTextChunk() {
        let line = #"""
        {"type":"assistant","message":{"content":[{"type":"text","text":"안녕하세요"}]},"session_id":"x","uuid":"y"}
        """#
        let chunks = ClaudeStreamParser.parse(line: line)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].kind, .text)
        XCTAssertEqual(chunks[0].content, "안녕하세요")
    }

    func testAssistantThinkingBlockYieldsThinkingChunk() {
        let line = #"""
        {"type":"assistant","message":{"content":[{"type":"thinking","thinking":"내부 사고"}]}}
        """#
        let chunks = ClaudeStreamParser.parse(line: line)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].kind, .thinking)
        XCTAssertEqual(chunks[0].content, "내부 사고")
    }

    func testAssistantToolUseSerializesPayloadAsJSON() {
        let line = #"""
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file":"/tmp/x"}}]}}
        """#
        let chunks = ClaudeStreamParser.parse(line: line)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].kind, .toolUse)
        let content = chunks[0].content
        XCTAssertTrue(content.contains("Read"), "missing Read in: \(content)")
        XCTAssertTrue(content.contains("tool_use"), "missing tool_use in: \(content)")
        // JSONSerialization 은 forward slash 를 \/ 로 escape — feature 가 아닌 대응 사항.
        XCTAssertTrue(
            content.contains("/tmp/x") || content.contains(#"\/tmp\/x"#),
            "missing path in: \(content)"
        )
    }

    func testUserToolResultYieldsToolResultChunk() {
        let line = #"""
        {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"result text"}]}}
        """#
        let chunks = ClaudeStreamParser.parse(line: line)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].kind, .toolResult)
        XCTAssertTrue(chunks[0].content.contains("\"tool_use_id\":\"t1\""))
    }

    func testResultSuccessYieldsCompletionWithReason() {
        let line = #"""
        {"type":"result","subtype":"success","is_error":false,"result":"done","stop_reason":"end_turn"}
        """#
        let chunks = ClaudeStreamParser.parse(line: line)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].kind, .completion)
        XCTAssertEqual(chunks[0].content, "end_turn")
    }

    func testResultErrorYieldsErrorChunk() {
        let line = #"""
        {"type":"result","subtype":"error","is_error":true,"result":"auth failed"}
        """#
        let chunks = ClaudeStreamParser.parse(line: line)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].kind, .error)
        XCTAssertEqual(chunks[0].content, "auth failed")
    }

    func testSystemEventsAreIgnored() {
        for line in [
            #"{"type":"system","subtype":"hook_started","hook_id":"x"}"#,
            #"{"type":"system","subtype":"init","tools":[]}"#,
            #"{"type":"system","subtype":"hook_response"}"#,
        ] {
            XCTAssertTrue(ClaudeStreamParser.parse(line: line).isEmpty, "system 이벤트 스킵 실패: \(line)")
        }
    }

    func testMalformedLineYieldsEmpty() {
        XCTAssertTrue(ClaudeStreamParser.parse(line: "not json").isEmpty)
        XCTAssertTrue(ClaudeStreamParser.parse(line: "").isEmpty)
        XCTAssertTrue(ClaudeStreamParser.parse(line: "{}").isEmpty)  // type 없음
    }

    func testUnknownTypeIgnored() {
        let line = #"{"type":"future_unknown_event","payload":{"x":1}}"#
        XCTAssertTrue(ClaudeStreamParser.parse(line: line).isEmpty)
    }

    func testMultipleContentBlocksAllYielded() {
        let line = #"""
        {"type":"assistant","message":{"content":[{"type":"text","text":"a"},{"type":"text","text":"b"},{"type":"thinking","thinking":"c"}]}}
        """#
        let chunks = ClaudeStreamParser.parse(line: line)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].content, "a")
        XCTAssertEqual(chunks[1].content, "b")
        XCTAssertEqual(chunks[2].kind, .thinking)
    }

    // extractFinalResultText: simplify 단계에서 미사용으로 제거됨.
}
