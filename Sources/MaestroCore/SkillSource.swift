import Foundation

/// `~/.claude/skills/<skill-name>/SKILL.md` 디렉토리 구조를 스캔.
///
/// 각 하위 디렉토리가 하나의 스킬 — `SKILL.md` 파일에 frontmatter (`name`, `description`)
/// 가 있어야 함. `name` 이 명시되지 않으면 디렉토리 이름 사용.
///
/// ## 보안
/// - 디렉토리 이름 / `name` frontmatter 모두 검증.
/// - 1 MiB 사이즈 cap.
/// - 심볼릭 링크 무시 (skipsHiddenFiles).
public struct SkillSource: SlashCommandSource {
    public let directory: URL
    public let maxFileBytes: Int

    public init(
        directory: URL,
        maxFileBytes: Int = 1 * 1024 * 1024
    ) {
        self.directory = directory
        self.maxFileBytes = max(1, maxFileBytes)
    }

    /// 사용자 글로벌 skills 디렉토리 — `~/.claude/skills/`
    public static func defaultUserSkillsURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".claude/skills", directoryHint: .isDirectory)
    }

    public func discover() async -> [DiscoveredSlashCommand] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [DiscoveredSlashCommand] = []
        let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for skillDir in sorted {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: skillDir.path, isDirectory: &isDir),
                  isDir.boolValue
            else { continue }

            let dirName = skillDir.lastPathComponent
            guard isValidSkillDirName(dirName) else { continue }

            let skillFile = skillDir.appending(
                path: "SKILL.md", directoryHint: .notDirectory
            )
            let resourceValues = try? skillFile.resourceValues(forKeys: [.fileSizeKey])
            if let size = resourceValues?.fileSize, size > maxFileBytes { continue }

            guard let raw = try? String(contentsOf: skillFile, encoding: .utf8) else {
                continue
            }
            let parsed = SlashCommandFrontmatter.parse(raw)
            let frontmatterName = parsed.fields["name"]
            let name = frontmatterName ?? dirName
            guard isValidSkillName(name) else { continue }
            let description = parsed.fields["description"] ?? ""

            let cmd = SlashCommand(
                name: name,
                description: description,
                category: SlashCommandSourceKind.skill.rawValue
            )
            result.append(
                DiscoveredSlashCommand(command: cmd, source: .skill, filePath: skillFile)
            )
        }
        return result
    }

    private func isValidSkillDirName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128, !name.hasPrefix(".") else { return false }
        return !name.contains("/") && !name.contains("\\") && !name.contains("..")
    }

    private func isValidSkillName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128, !name.hasPrefix(".") else { return false }
        return !name.contains("/") && !name.contains("\\") && !name.contains("..")
    }
}
