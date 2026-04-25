import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class ClaudeJSONResultTests: XCTestCase {
    func testDecodesSuccessResponse() throws {
        let raw = #"""
        {"type":"result","subtype":"success","is_error":false,"result":"Hello!","session_id":"abc-123","stop_reason":"end_turn","duration_ms":1633}
        """#
        let result = try ClaudeJSONResult.decode(from: raw)
        XCTAssertEqual(result.type, "result")
        XCTAssertEqual(result.subtype, "success")
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.result, "Hello!")
        XCTAssertEqual(result.sessionId, "abc-123")
        XCTAssertEqual(result.stopReason, "end_turn")
        XCTAssertEqual(result.durationMs, 1633)
    }

    func testDecodesIgnoresUnknownFields() throws {
        // Claude CLI 가 새 필드 도입해도 디코드 실패하지 않아야 함.
        let raw = #"""
        {"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"x","new_future_field":42,"usage":{"input_tokens":3}}
        """#
        let result = try ClaudeJSONResult.decode(from: raw)
        XCTAssertEqual(result.result, "ok")
    }

    func testValidatedResultTextThrowsOnError() throws {
        let result = ClaudeJSONResult(
            type: "result", subtype: "error",
            isError: true, result: "auth failed",
            sessionId: nil, stopReason: nil, durationMs: nil
        )
        do {
            _ = try result.validatedResultText()
            XCTFail("expected claudeReportedError")
        } catch let err as ClaudeResponseError {
            if case .claudeReportedError(let subtype, let msg) = err {
                XCTAssertEqual(subtype, "error")
                XCTAssertEqual(msg, "auth failed")
            } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testValidatedResultTextThrowsOnMissingResult() throws {
        let result = ClaudeJSONResult(
            type: "result", subtype: "success",
            isError: false, result: nil,
            sessionId: "x", stopReason: nil, durationMs: nil
        )
        do {
            _ = try result.validatedResultText()
            XCTFail("expected missingResultText")
        } catch ClaudeResponseError.missingResultText {
            // OK
        }
    }

    func testMalformedJSONThrows() throws {
        do {
            _ = try ClaudeJSONResult.decode(from: "not json {]")
            XCTFail("expected malformedJSON")
        } catch let err as ClaudeResponseError {
            if case .malformedJSON = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testSubtypeErrorButIsErrorFalse() throws {
        // is_error=false 인데 subtype 이 "error" 인 엣지 케이스 — 거부.
        let result = ClaudeJSONResult(
            type: "result", subtype: "error",
            isError: false, result: "boom",
            sessionId: nil, stopReason: nil, durationMs: nil
        )
        do {
            _ = try result.validatedResultText()
            XCTFail("expected claudeReportedError")
        } catch ClaudeResponseError.claudeReportedError { /* OK */ }
    }
}
