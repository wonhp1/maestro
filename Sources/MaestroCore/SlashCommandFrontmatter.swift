import Foundation

/// `~/.claude/commands/*.md` / `~/.claude/skills/*/SKILL.md` 의 YAML frontmatter
/// 파서. 외부 YAML 의존성 없이 우리 용도(scalar key/value)만 지원하는 minimal 구현.
///
/// ## 형식
/// ```
/// ---
/// description: Compacts the conversation
/// argument-hint: [topic]
/// ---
/// (body)
/// ```
///
/// - frontmatter 가 없거나 닫는 `---` 가 누락되면 `fields` 는 비어 있고 `body` 는 원본.
/// - 같은 key 가 두 번 나타나면 마지막 값이 채택.
/// - 따옴표(`"...", '...'`) 로 감싼 값은 unquote.
public enum SlashCommandFrontmatter {
    public struct Parsed: Sendable, Equatable {
        public let fields: [String: String]
        public let body: String
    }

    public static func parse(_ raw: String) -> Parsed {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---"
        else {
            return Parsed(fields: [:], body: raw)
        }

        var fields: [String: String] = [:]
        var endIdx: Int = -1
        var i = 1
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                endIdx = i
                break
            }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    fields[key.lowercased()] = unquote(value)
                }
            }
            i += 1
        }
        guard endIdx >= 0 else { return Parsed(fields: [:], body: raw) }
        let bodyLines = lines[(endIdx + 1)...]
        let body = bodyLines.joined(separator: "\n")
        return Parsed(fields: fields, body: body)
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        if s.first == "\"" && s.last == "\"" {
            return String(s.dropFirst().dropLast())
        }
        if s.first == "'" && s.last == "'" {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
