import Foundation

/// 커맨드 팔레트의 한 항목.
///
/// `id` 는 stable identifier — 최근 사용 추적 / 단축키 매핑의 키.
/// `handler` 는 `@Sendable` async closure — 사용자 선택 시 호출.
public struct Command: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let category: CommandCategory
    public let shortcutHint: String?
    public let handler: @Sendable @MainActor () async -> Void

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        category: CommandCategory,
        shortcutHint: String? = nil,
        handler: @escaping @Sendable @MainActor () async -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.shortcutHint = shortcutHint
        self.handler = handler
    }
}

public enum CommandCategory: String, Sendable, CaseIterable {
    /// 폴더 전환 (`⌘1`~`⌘9`)
    case folder
    /// 에이전트로 메시지 보내기
    case dispatch
    /// 토론 시작 / 일시정지 / 종료
    case discussion
    /// 슬래시 명령 (`~/.claude/commands`, 내장, 스킬)
    case slash
    /// 설정 / 진단 / 도움말
    case system
    /// 최근 사용 (자동 채워짐)
    case recent

    public var localizedName: String {
        switch self {
        case .folder: return "폴더"
        case .dispatch: return "보내기"
        case .discussion: return "토론"
        case .slash: return "슬래시"
        case .system: return "시스템"
        case .recent: return "최근"
        }
    }

    public var sortPriority: Int {
        switch self {
        case .recent: return 0
        case .folder: return 1
        case .slash: return 2
        case .dispatch: return 3
        case .discussion: return 4
        case .system: return 5
        }
    }
}

/// 커맨드 소스 — 폴더, 어댑터, 토론 등 각 도메인이 구현.
///
/// `commands()` 는 호출 시점의 snapshot 반환 — Provider 가 외부 상태 (folders 등)
/// 를 캡처해서 closure 안에서 fresh 하게 읽으면 됨.
public protocol CommandProvider: Sendable {
    func commands() async -> [Command]
}
