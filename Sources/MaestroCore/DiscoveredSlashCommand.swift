import Foundation

/// 슬래시 명령의 출처 — UI 그룹핑 + 무효화 정책 결정에 사용.
public enum SlashCommandSourceKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// `~/.claude/commands/*.md`
    case userFile
    /// `<folder>/.claude/commands/*.md` (Phase 17 defer)
    case projectFile
    /// `claude -p "/help"` 로 프로빙된 내장 명령
    case builtin
    /// `~/.claude/skills/*/SKILL.md`
    case skill

    /// SlashCommandRegistry 정렬 우선순위 — 작을수록 위.
    public var sortPriority: Int {
        switch self {
        case .builtin: return 0
        case .userFile: return 1
        case .projectFile: return 2
        case .skill: return 3
        }
    }

    public var displayLabel: String {
        switch self {
        case .builtin: return "내장"
        case .userFile: return "사용자"
        case .projectFile: return "프로젝트"
        case .skill: return "스킬"
        }
    }
}

/// 단일 슬래시 명령 발견 결과 — `SlashCommand` (메타데이터) + 출처 + 파일 위치.
///
/// `id` 는 `<source>:<name>` — 같은 이름이 여러 출처에 있을 수 있음 (예: 사용자가
/// 내장 명령을 override).
public struct DiscoveredSlashCommand: Sendable, Hashable, Identifiable, Codable {
    public let command: SlashCommand
    public let source: SlashCommandSourceKind
    public let filePath: URL?

    public var id: String { "\(source.rawValue):\(command.name)" }

    public init(
        command: SlashCommand,
        source: SlashCommandSourceKind,
        filePath: URL? = nil
    ) {
        self.command = command
        self.source = source
        self.filePath = filePath
    }
}

/// 슬래시 명령 발견 책임 — 파일 시스템 / 외부 프로세스 등 각 출처가 구현.
///
/// 한 번의 호출로 현재 시점의 snapshot 반환. 캐싱은 구현체 또는 `SlashCommandRegistry`
/// 가 책임.
public protocol SlashCommandSource: Sendable {
    func discover() async -> [DiscoveredSlashCommand]
}
