import Foundation
import MaestroCore

/// `claude -p ... --output-format json` 의 단일 JSON 결과 객체.
///
/// 예시:
/// ```json
/// {
///   "type": "result",
///   "subtype": "success" | "error",
///   "is_error": false,
///   "result": "응답 텍스트",
///   "session_id": "uuid",
///   "stop_reason": "end_turn",
///   "duration_ms": 1633,
///   "usage": { ... },
///   "total_cost_usd": 0.08
/// }
/// ```
///
/// 알 수 없는 필드는 무시 (Codable 기본 동작) — Claude CLI 가 추가 필드를 도입해도 호환.
public struct ClaudeJSONResult: Codable, Hashable, Sendable {
    public let type: String
    public let subtype: String
    public let isError: Bool
    public let result: String?
    public let sessionId: String?
    public let stopReason: String?
    public let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case subtype
        case isError = "is_error"
        case result
        case sessionId = "session_id"
        case stopReason = "stop_reason"
        case durationMs = "duration_ms"
    }

    public init(
        type: String,
        subtype: String,
        isError: Bool,
        result: String?,
        sessionId: String?,
        stopReason: String?,
        durationMs: Int?
    ) {
        self.type = type
        self.subtype = subtype
        self.isError = isError
        self.result = result
        self.sessionId = sessionId
        self.stopReason = stopReason
        self.durationMs = durationMs
    }
}

/// JSON 본문 (또는 단일 라인) 디코드 실패 / 의미적 오류.
public enum ClaudeResponseError: Error, Equatable, Sendable {
    /// Claude 가 비-JSON 출력 (e.g., 인증 실패 메시지) 을 stdout 으로 흘림.
    case malformedJSON(snippet: String)
    /// JSON 은 valid 하지만 Claude 가 `is_error: true` 또는 `subtype: "error"` 반환.
    case claudeReportedError(subtype: String, message: String)
    /// 결과 텍스트가 없음 — 비정상 응답.
    case missingResultText
}

public extension ClaudeJSONResult {
    /// 단일 JSON 객체 raw 문자열을 파싱.
    /// 비-JSON 또는 디코드 실패 → `malformedJSON`.
    static func decode(from raw: String) throws -> ClaudeJSONResult {
        guard let data = raw.data(using: .utf8) else {
            throw ClaudeResponseError.malformedJSON(snippet: String(raw.prefix(120)))
        }
        do {
            return try JSONDecoder().decode(ClaudeJSONResult.self, from: data)
        } catch {
            throw ClaudeResponseError.malformedJSON(snippet: String(raw.prefix(120)))
        }
    }

    /// 의미 검증 — `is_error` true 또는 result 누락 시 throws.
    func validatedResultText() throws -> String {
        if isError || subtype == "error" {
            throw ClaudeResponseError.claudeReportedError(
                subtype: subtype,
                message: result ?? "<no message>"
            )
        }
        guard let text = result, !text.isEmpty else {
            throw ClaudeResponseError.missingResultText
        }
        return text
    }
}
