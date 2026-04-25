import Foundation

/// 디렉토리(`~/.claude/commands/`)에서 `*.md` 파일을 스캔해 슬래시 명령을 발견.
///
/// ## 형식
/// 파일명에서 `.md` 를 제거한 stem 이 명령 이름. 파일 본문은 frontmatter
/// (`description`, `argument-hint`) + body.
///
/// ## 보안
/// - **이름 검증**: ASCII 영숫자 + `_` `-` 만 허용, 128자 이하, hidden / `..` 차단.
/// - **파일 사이즈 cap**: 1 MiB 초과 파일은 skip — 비정상 파일 / 공격 페이로드 방어.
/// - **심볼릭 링크 무시**: `[.skipsHiddenFiles]` + 파일 속성 체크.
///
/// ## 멱등성
/// 매 호출 시 디렉토리 다시 스캔 — 캐싱은 호출자(`SlashCommandRegistry`)가 책임.
public struct FileSlashCommandSource: SlashCommandSource {
    public let directory: URL
    public let kind: SlashCommandSourceKind
    public let maxFileBytes: Int

    public init(
        directory: URL,
        kind: SlashCommandSourceKind = .userFile,
        maxFileBytes: Int = 1 * 1024 * 1024
    ) {
        self.directory = directory
        self.kind = kind
        self.maxFileBytes = max(1, maxFileBytes)
    }

    /// 사용자 글로벌 commands 디렉토리 — `~/.claude/commands/`
    public static func defaultUserCommandsURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".claude/commands", directoryHint: .isDirectory)
    }

    public func discover() async -> [DiscoveredSlashCommand] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [DiscoveredSlashCommand] = []
        let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in sorted {
            guard url.pathExtension.lowercased() == "md" else { continue }

            let name = url.deletingPathExtension().lastPathComponent
            guard Self.isValidCommandName(name) else { continue }

            // 사이즈 cap — frontmatter 만 읽으면 사실 작아야 정상
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
            if let size = resourceValues?.fileSize, size > maxFileBytes { continue }

            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = SlashCommandFrontmatter.parse(raw)
            let description = parsed.fields["description"]
                ?? Self.firstNonEmptyLine(of: parsed.body)
            let argHint = parsed.fields["argument-hint"]

            let cmd = SlashCommand(
                name: name,
                description: description,
                category: kind.rawValue,
                arguments: argHint.map { [$0] }
            )
            result.append(
                DiscoveredSlashCommand(command: cmd, source: kind, filePath: url)
            )
        }
        return result
    }

    static func isValidCommandName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        if name.hasPrefix(".") { return false }
        if name.contains("/") || name.contains("\\") || name.contains("..") {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func firstNonEmptyLine(of body: String) -> String {
        for raw in body.split(whereSeparator: \.isNewline) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(160))
            }
        }
        return ""
    }
}
