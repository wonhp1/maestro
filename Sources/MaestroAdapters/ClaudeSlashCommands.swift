import Foundation
import MaestroCore

/// `~/.claude/commands/` 와 프로젝트 `<folder>/.claude/commands/` 의 .md 파일을 슬래시 명령으로 노출.
///
/// 추가로 Claude Code 에 hardcoded 된 built-in 명령 목록 노출.
public enum ClaudeSlashCommands {
    /// 자주 쓰이는 built-in 명령. 정확한 풀 리스트는 Claude CLI 의 system init 이벤트에서 발견되지만,
    /// 그 이벤트를 얻으려면 CLI 한 번 spawn 해야 함 → 정적 목록으로 baseline 제공.
    public static let builtIns: [SlashCommand] = [
        SlashCommand(name: "clear", description: "Clear context", category: "built-in"),
        SlashCommand(name: "compact", description: "Compact conversation", category: "built-in"),
        SlashCommand(name: "context", description: "Show context window state", category: "built-in"),
        SlashCommand(name: "init", description: "Initialize CLAUDE.md", category: "built-in"),
        SlashCommand(name: "review", description: "Review recent changes", category: "built-in"),
        SlashCommand(name: "security-review", description: "Security audit", category: "built-in"),
        SlashCommand(name: "usage", description: "Token / cost usage", category: "built-in"),
        SlashCommand(name: "insights", description: "Conversation insights", category: "built-in"),
        SlashCommand(name: "team-onboarding", description: "Team onboarding flow", category: "built-in"),
        SlashCommand(name: "extra-usage", description: "Extra usage details", category: "built-in"),
    ]

    /// 디렉토리 안 .md 파일 → SlashCommand 목록.
    /// - 파일이름 (확장자 제거) 이 명령 이름.
    /// - 첫 번째 비어있지 않은 라인이 description (frontmatter `---` block 은 skip).
    /// - 디렉토리가 없거나 읽기 실패 → 빈 배열.
    /// - **보안**: 심볼릭 링크는 거부 (`/etc/passwd` 노출 방지). 파일 내용 읽기는 16 KiB cap.
    public static func scan(directory: URL, category: String) -> [SlashCommand] {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir),
              isDir.boolValue,
              let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return entries
            .filter { $0.pathExtension.lowercased() == "md" }
            .filter { !isSymbolicLink($0) }  // Phase 7 must-fix: 심볼릭 링크 거부
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in slashCommand(from: url, category: category) }
    }

    /// 단일 라인 description 읽기 cap — 큰 markdown 도 16 KiB 만 읽고 폐기.
    private static let maxReadBytes = 16 * 1024

    private static func isSymbolicLink(_ url: URL) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func slashCommand(from url: URL, category: String) -> SlashCommand? {
        let name = url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty else { return nil }
        let description = firstMeaningfulLine(of: url) ?? "User command"
        return SlashCommand(name: name, description: description, category: category)
    }

    /// frontmatter (`---` 사이) 를 skip 하고 첫 비어있지 않은 라인 반환. nil 가능.
    /// 파일 첫 `maxReadBytes` 만 읽음 — 큰 markdown 의 OOM/지연 방어 (Phase 7 must-fix).
    private static func firstMeaningfulLine(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxReadBytes), !data.isEmpty else {
            return nil
        }
        let content = String(decoding: data, as: UTF8.self)
        var inFrontmatter = false
        var sawFrontmatterStart = false
        for raw in content.split(separator: "\n", maxSplits: Int.max, omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" {
                if !sawFrontmatterStart {
                    sawFrontmatterStart = true
                    inFrontmatter = true
                    continue
                } else if inFrontmatter {
                    inFrontmatter = false
                    continue
                }
            }
            if inFrontmatter || line.isEmpty { continue }
            // # 헤더 prefix 제거 (markdown convention).
            return line.hasPrefix("#")
                ? line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                : line
        }
        return nil
    }
}
