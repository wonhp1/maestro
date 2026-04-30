import Foundation
import MaestroCore

/// v0.9.0 — Google Gemini CLI (`gemini -p ... -o stream-json`) 의 NDJSON 한 줄.
///
/// 실제 캡처된 event types:
/// - `init` — `{ session_id, model, timestamp }` (세션 시작)
/// - `message` (role=user) — `{ content }` (사용자 prompt echo)
/// - `message` (role=assistant, delta=true) — `{ content }` (응답 chunk)
/// - `tool_use` — TBD (Phase 3C 검증)
/// - `tool_result` — TBD
/// - `result` — `{ status, stats }` (최종 통계)
/// - `error` — TBD
public struct GeminiStreamEvent: Codable, Sendable, Equatable {
    public let type: String
    public let timestamp: String?
    public let sessionId: String?
    public let model: String?
    public let role: String?
    public let content: String?
    public let delta: Bool?
    public let status: String?
    public let stats: GeminiStats?
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case sessionId = "session_id"
        case model
        case role
        case content
        case delta
        case status
        case stats
        case message
    }
}

public struct GeminiStats: Codable, Sendable, Equatable {
    public let totalTokens: Int?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cached: Int?
    public let durationMs: Int?
    public let toolCalls: Int?

    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cached
        case durationMs = "duration_ms"
        case toolCalls = "tool_calls"
    }
}

// MARK: - Parser

public enum GeminiStreamParser {
    public static func parse(line: String) -> GeminiStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GeminiStreamEvent.self, from: data)
    }

    public static func parseAll(stdout: String) -> [GeminiStreamEvent] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parse(line: String($0)) }
    }

    /// events 에서 assistant 응답을 모두 합쳐서 반환 (delta chunks 통합).
    public static func extractFinalAssistantText(events: [GeminiStreamEvent]) -> String? {
        let texts = events.compactMap { event -> String? in
            guard event.type == "message",
                  event.role == "assistant",
                  let content = event.content else { return nil }
            return content
        }
        return texts.isEmpty ? nil : texts.joined()
    }

    public static func extractSessionId(events: [GeminiStreamEvent]) -> String? {
        for event in events where event.type == "init" {
            if let id = event.sessionId { return id }
        }
        return nil
    }

    public static func extractModel(events: [GeminiStreamEvent]) -> String? {
        for event in events where event.type == "init" {
            if let model = event.model { return model }
        }
        return nil
    }

    public static func extractError(events: [GeminiStreamEvent]) -> String? {
        for event in events where event.type == "error" {
            if let msg = event.message { return msg }
        }
        return nil
    }

    /// 단일 event → ResponseChunk 배열 변환. Codex 패턴과 동일한 인터페이스.
    public static func chunks(from event: GeminiStreamEvent) -> [ResponseChunk] {
        switch event.type {
        case "message":
            // user echo 는 UI 에 표시 X.
            guard event.role == "assistant",
                  let content = event.content else { return [] }
            return [ResponseChunk.text(content)]
        case "result":
            return [ResponseChunk.completion()]
        default:
            return []
        }
    }
}

public enum GeminiResponseError: Error, Equatable, Sendable {
    case missingAssistantText(snippet: String)
    case geminiReportedError(message: String)
    case malformedOutput(snippet: String)
}
