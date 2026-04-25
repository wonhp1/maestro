import Foundation
import MaestroCore

/// `claude --output-format stream-json --verbose` 의 라인 별 이벤트 파싱.
///
/// 각 라인이 단일 JSON 객체. 주요 type:
/// - `system` (subtype: `init` / `hook_started` / `hook_response` / ...) — 시스템 이벤트
/// - `assistant` — `message.content[*]` 안에 `text`/`thinking`/`tool_use` 블록
/// - `user` — 툴 결과 회신 (`tool_result`)
/// - `result` — 최종 결과 (subtype `success`/`error`)
///
/// 알 수 없는 타입은 무시 (defensive parsing — Claude CLI 추가 type 호환).
public enum ClaudeStreamParser {
    /// 한 라인을 0개 이상의 `ResponseChunk` 로 변환.
    /// 디코드 실패 라인은 빈 배열 (silent — 호출자가 판단).
    public static func parse(line: String) -> [ResponseChunk] {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return []
        }
        switch type {
        case "assistant":
            return assistantChunks(from: json)
        case "user":
            return userChunks(from: json)
        case "result":
            return resultChunks(from: json)
        default:
            return []  // system / unknown
        }
    }

    // MARK: - Block extractors

    /// `assistant.message.content[*]` 의 각 블록 → ResponseChunk.
    /// - text → .text
    /// - thinking → .thinking
    /// - tool_use → .toolUse (JSON encoded)
    private static func assistantChunks(from json: [String: Any]) -> [ResponseChunk] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }
        var chunks: [ResponseChunk] = []
        for block in content {
            guard let blockType = block["type"] as? String else { continue }
            switch blockType {
            case "text":
                if let text = block["text"] as? String {
                    chunks.append(.text(text))
                }
            case "thinking":
                if let thinking = block["thinking"] as? String {
                    chunks.append(ResponseChunk(kind: .thinking, content: thinking))
                }
            case "tool_use":
                let payload = serializeJSON(block)
                chunks.append(ResponseChunk(kind: .toolUse, content: payload))
            default:
                continue
            }
        }
        return chunks
    }

    /// `user.message.content[*]` 의 `tool_result` 블록 → .toolResult.
    private static func userChunks(from json: [String: Any]) -> [ResponseChunk] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }
        var chunks: [ResponseChunk] = []
        for block in content where block["type"] as? String == "tool_result" {
            chunks.append(ResponseChunk(kind: .toolResult, content: serializeJSON(block)))
        }
        return chunks
    }

    /// 최종 result 이벤트 → .completion (reason 으로 stop_reason 첨부).
    /// is_error 인 경우 .error 청크.
    private static func resultChunks(from json: [String: Any]) -> [ResponseChunk] {
        let isError = (json["is_error"] as? Bool) ?? false
        if isError {
            let msg = (json["result"] as? String) ?? "<no message>"
            return [ResponseChunk(kind: .error, content: msg)]
        }
        let reason = (json["stop_reason"] as? String) ?? ""
        return [ResponseChunk.completion(reason: reason)]
    }

    private static func serializeJSON(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
