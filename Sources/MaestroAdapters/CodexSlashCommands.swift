import Foundation
import MaestroCore

/// v0.9.0 Phase 2D — Codex CLI 의 정적 + 동적 슬래시 명령 collection.
///
/// Codex CLI 는 Claude 와 달리 비대화형 (`exec`) 모드에서 builtin 슬래시 명령을
/// JSONL 로 노출하지 않음. 대신:
/// - 정적 builtin 명령 (Maestro 가 알고 있는 표준 동작)
/// - `~/.codex/skills/` 의 사용자 / 시스템 skills 스캔
public enum CodexSlashCommands {
    /// Codex 의 일반적으로 알려진 builtin 명령 — UI popover 에 노출.
    /// 인터랙티브 TUI 가 지원하는 것 기준 (실제 동작 확인 필요).
    public static let builtIns: [SlashCommand] = [
        SlashCommand(
            name: "/help",
            description: "Codex 명령 도움말",
            category: "builtin"
        ),
        SlashCommand(
            name: "/clear",
            description: "현재 세션 컨텍스트 초기화",
            category: "builtin"
        ),
        SlashCommand(
            name: "/model",
            description: "모델 선택 (gpt-5.5, gpt-5.4 등)",
            category: "builtin"
        ),
        SlashCommand(
            name: "/login",
            description: "OpenAI 계정 로그인",
            category: "builtin"
        ),
    ]

    /// `~/.codex/skills/` 또는 그 하위 `.system/` 의 skills 스캔.
    /// 각 skill 디렉토리는 SKILL.md 또는 동등 metadata 포함.
    /// - Parameter directory: skill 들의 루트 디렉토리 (예: `~/.codex/skills`).
    /// - Returns: SlashCommand 배열 (각 디렉토리 이름 = command name).
    public static func scan(directory: URL, category: String) -> [SlashCommand] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [SlashCommand] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDir {
                let skillName = entry.lastPathComponent
                let description = readSkillDescription(at: entry) ?? "Codex skill"
                results.append(SlashCommand(
                    name: "/\(skillName)",
                    description: description,
                    category: category
                ))
            }
        }
        return results.sorted { $0.name < $1.name }
    }

    /// SKILL.md 또는 비슷한 metadata 파일에서 `description:` 라인 추출.
    /// 없으면 nil → 기본 메시지 사용.
    private static func readSkillDescription(at directory: URL) -> String? {
        let candidates = ["SKILL.md", "skill.md", "README.md"]
        for filename in candidates {
            let path = directory.appending(path: filename, directoryHint: .notDirectory)
            guard let content = try? String(contentsOf: path, encoding: .utf8) else { continue }
            // YAML frontmatter 의 description 추출
            for line in content.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("description:") {
                    let value = trimmed.dropFirst("description:".count)
                        .trimmingCharacters(in: .whitespaces)
                    return value.isEmpty ? nil : String(value)
                }
            }
        }
        return nil
    }
}
