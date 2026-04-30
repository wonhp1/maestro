import Foundation
import MaestroCore

/// v0.9.0 — Codex CLI (`codex exec --json`) 의 NDJSON 한 줄 = 1 event.
///
/// 실제 캡처된 event types:
/// - `thread.started` — `{ thread_id }` (UUID, 향후 resume 키)
/// - `turn.started` — payload 없음
/// - `item.started` — `{ item: { id, type, ... } }` (status=in_progress)
/// - `item.completed` — `{ item: { id, type, status, ... } }`
///   - `item.type=agent_message` → `{ text }`
///   - `item.type=command_execution` → `{ command, aggregated_output, exit_code, status }`
/// - `turn.completed` — `{ usage: { input_tokens, ... } }`
/// - `turn.failed` — `{ error: { message } }`
/// - `error` — `{ message }`
///
/// 모든 필드 optional — Codex CLI 가 새 event type / 필드 추가해도 호환.
public struct CodexStreamEvent: Codable, Sendable, Equatable {
    public let type: String
    public let threadId: String?
    public let item: CodexItem?
    public let usage: CodexUsage?
    public let message: String?
    public let error: CodexErrorPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case threadId = "thread_id"
        case item
        case usage
        case message
        case error
    }
}

/// `item.started` / `item.completed` 의 item payload.
public struct CodexItem: Codable, Sendable, Equatable {
    public let id: String
    public let type: String
    public let text: String?
    public let command: String?
    public let aggregatedOutput: String?
    public let exitCode: Int?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case text
        case command
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
        case status
    }

    /// agent_message 의 응답 텍스트. 다른 type 은 nil.
    public var agentMessageText: String? {
        type == "agent_message" ? text : nil
    }

    /// command_execution 의 요약 (UI 표시용).
    public var commandSummary: String? {
        guard type == "command_execution", let cmd = command else { return nil }
        return cmd
    }
}

/// `turn.completed` 의 usage 통계.
public struct CodexUsage: Codable, Sendable, Equatable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
    }
}

/// `turn.failed` 의 에러 payload.
public struct CodexErrorPayload: Codable, Sendable, Equatable {
    public let message: String
}

// MARK: - Parser

/// JSONL 한 줄 → CodexStreamEvent 디코딩 + 의미적 분류 helper.
public enum CodexStreamParser {
    /// 단일 line 파싱. 빈 줄 / 비-JSON / 알 수 없는 type → nil (skip).
    public static func parse(line: String) -> CodexStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CodexStreamEvent.self, from: data)
    }

    /// JSONL 전체 stdout 파싱 → event 배열.
    /// 비-JSON 라인은 skip (Codex CLI 가 가끔 stderr 같은 plaintext 섞어 출력).
    public static func parseAll(stdout: String) -> [CodexStreamEvent] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parse(line: String($0)) }
    }

    /// events 에서 마지막 agent_message 텍스트 추출. 없으면 nil.
    public static func extractFinalAgentMessage(events: [CodexStreamEvent]) -> String? {
        for event in events.reversed() where event.type == "item.completed" {
            if let text = event.item?.agentMessageText { return text }
        }
        return nil
    }

    /// events 에서 thread_id 추출 (thread.started event 의 첫 번째).
    public static func extractThreadId(events: [CodexStreamEvent]) -> String? {
        for event in events where event.type == "thread.started" {
            if let id = event.threadId { return id }
        }
        return nil
    }

    /// events 에 turn.failed 또는 error 가 있으면 message 반환.
    public static func extractError(events: [CodexStreamEvent]) -> String? {
        for event in events {
            if event.type == "turn.failed", let msg = event.error?.message {
                return msg
            }
            if event.type == "error", let msg = event.message {
                return msg
            }
        }
        return nil
    }

    /// v0.9.0 Phase 2C — 단일 event → UI 가 보여줄 ResponseChunk 배열.
    /// 한 event 가 0~N 개 chunk 생성 가능 (대부분 0 or 1).
    ///
    /// - `thread.started` / `turn.started` → 빈 배열 (UI 표시 X)
    /// - `item.started` (command_execution) → toolUse chunk (실행 중인 명령)
    /// - `item.completed` (command_execution) → toolResult chunk (출력 + exit code)
    /// - `item.completed` (agent_message) → text chunk
    /// - `turn.completed` → completion chunk
    /// - `error` / `turn.failed` → 빈 배열 (호출자가 throw 처리)
    public static func chunks(from event: CodexStreamEvent) -> [ResponseChunk] {
        switch event.type {
        case "item.started":
            guard let item = event.item, item.type == "command_execution",
                  let cmd = item.command else { return [] }
            // toolUse JSON: {"command": "...", "status": "in_progress"}
            let payload = """
                {"command":\(jsonString(cmd)),"status":"in_progress"}
                """
            return [ResponseChunk(kind: .toolUse, content: payload)]
        case "item.completed":
            guard let item = event.item else { return [] }
            switch item.type {
            case "agent_message":
                guard let text = item.text else { return [] }
                return [ResponseChunk.text(text)]
            case "command_execution":
                let output = item.aggregatedOutput ?? ""
                let exitCode = item.exitCode.map(String.init) ?? "?"
                let payload = """
                    {"output":\(jsonString(output)),"exit_code":\(exitCode)}
                    """
                return [ResponseChunk(kind: .toolResult, content: payload)]
            default:
                return []
            }
        case "turn.completed":
            return [ResponseChunk.completion()]
        default:
            return []
        }
    }

    /// JSON string literal 생성 — escape 처리.
    private static func jsonString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

/// CodexAdapter 가 throw 하는 Codex 특화 에러.
public enum CodexResponseError: Error, Equatable, Sendable {
    /// stdout 에 단 하나의 agent_message 도 없음 — 비정상 응답.
    case missingAgentMessage(snippet: String)
    /// Codex CLI 가 turn.failed 또는 error event 반환.
    case codexReportedError(message: String)
    /// stdout 디코드 실패 (모든 라인이 비-JSON).
    case malformedOutput(snippet: String)
}
