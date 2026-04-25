import Foundation

/// 사용자 노출 모든 텍스트의 중앙 카탈로그.
///
/// ## 설계
/// - 각 키는 `LocalizedKey` — `(key, ko, en)` 트리플.
/// - `localized()` 가 OS 의 현재 언어에 맞게 ko 또는 en 반환.
/// - `defaultLocalization: "ko"` (Package.swift), 미번역 키는 ko fallback.
/// - 새 사용자 텍스트 추가 시 반드시 이 카탈로그에 등록 → `LocalizationKeysTests`
///   가 모든 키의 ko/en 비어있지 않은지 + 중복 키 없는지 검증.
///
/// ## 마이그레이션
/// Phase 22 는 카탈로그 + 핵심 view 일부만 시범 적용. 나머지 view 는 Phase 23+ 점진
/// 마이그레이션. 이 카탈로그가 single source of truth — Xcode String Catalog
/// (xcstrings) 도입 시에도 같은 키 이름 그대로 export 가능.
public struct LocalizedKey: Sendable, Hashable {
    public let key: String
    public let ko: String
    public let en: String

    public init(key: String, ko: String, en: String) {
        self.key = key
        self.ko = ko
        self.en = en
    }

    /// 시스템 언어 우선. 한국어 prefix 면 ko, 그 외 en.
    public func localized(localeIdentifier: String? = nil) -> String {
        let langCode = (localeIdentifier ?? Locale.current.identifier)
            .split(separator: "_").first.map(String.init)?.lowercased()
            ?? "en"
        if langCode.hasPrefix("ko") { return ko }
        return en
    }

    /// SwiftUI `Text(_ key:)` 와 호환되도록 — production 에서는 `localized()` 사용 권장.
    public var bothLanguages: (ko: String, en: String) { (ko, en) }
}

/// 모든 사용자 노출 텍스트.
///
/// 카테고리별 nested enum — Onboarding / Preferences / Menu / Inbox / etc.
public enum LocalizationKeys {
    public enum App {
        public static let title = LocalizedKey(
            key: "app.title", ko: "Maestro", en: "Maestro"
        )
    }

    public enum Onboarding {
        public static let welcomeTitle = LocalizedKey(
            key: "onboarding.welcome.title",
            ko: "Maestro 에 오신 걸 환영합니다",
            en: "Welcome to Maestro"
        )
        public static let detectAgentsTitle = LocalizedKey(
            key: "onboarding.detect.title",
            ko: "에이전트 감지",
            en: "Detect Agents"
        )
        public static let firstFolderTitle = LocalizedKey(
            key: "onboarding.firstFolder.title",
            ko: "첫 폴더 추가",
            en: "Add First Folder"
        )
        public static let skip = LocalizedKey(
            key: "onboarding.skip", ko: "건너뛰기", en: "Skip"
        )
        public static let next = LocalizedKey(
            key: "onboarding.next", ko: "다음", en: "Next"
        )
        public static let start = LocalizedKey(
            key: "onboarding.start", ko: "시작", en: "Start"
        )
        public static let back = LocalizedKey(
            key: "onboarding.back", ko: "이전", en: "Back"
        )
        public static let addFolder = LocalizedKey(
            key: "onboarding.addFolder", ko: "폴더 추가…", en: "Add Folder…"
        )
    }

    public enum Menu {
        public static let newFolder = LocalizedKey(
            key: "menu.newFolder", ko: "새 폴더 추가…", en: "New Folder…"
        )
        public static let revealDataFolder = LocalizedKey(
            key: "menu.revealData", ko: "데이터 폴더 열기", en: "Open Data Folder"
        )
        public static let exportDiagnostics = LocalizedKey(
            key: "menu.exportDiag", ko: "진단 번들 내보내기…",
            en: "Export Diagnostics Bundle…"
        )
        public static let removeSelectedFolder = LocalizedKey(
            key: "menu.removeFolder", ko: "선택 폴더 제거", en: "Remove Selected Folder"
        )
        public static let preferences = LocalizedKey(
            key: "menu.preferences", ko: "환경설정…", en: "Preferences…"
        )
        public static let commandPalette = LocalizedKey(
            key: "menu.palette", ko: "커맨드 팔레트", en: "Command Palette"
        )
        public static let help = LocalizedKey(
            key: "menu.help", ko: "Maestro 도움말", en: "Maestro Help"
        )
    }

    public enum Preferences {
        public static let title = LocalizedKey(
            key: "prefs.title", ko: "환경설정", en: "Preferences"
        )
        public static let general = LocalizedKey(
            key: "prefs.general", ko: "일반", en: "General"
        )
        public static let agents = LocalizedKey(
            key: "prefs.agents", ko: "에이전트", en: "Agents"
        )
        public static let shortcuts = LocalizedKey(
            key: "prefs.shortcuts", ko: "단축키", en: "Shortcuts"
        )
        public static let advanced = LocalizedKey(
            key: "prefs.advanced", ko: "고급", en: "Advanced"
        )
        public static let notifications = LocalizedKey(
            key: "prefs.notif", ko: "시스템 알림 사용", en: "Use System Notifications"
        )
        public static let openInFinder = LocalizedKey(
            key: "prefs.openFinder", ko: "Finder 에서 열기", en: "Show in Finder"
        )
    }

    public enum Inbox {
        public static let empty = LocalizedKey(
            key: "inbox.empty", ko: "새 메시지 없음", en: "No new messages"
        )
        public static let unreadCount = LocalizedKey(
            key: "inbox.unread", ko: "미확인 메시지", en: "Unread messages"
        )
    }

    public enum Common {
        public static let cancel = LocalizedKey(
            key: "common.cancel", ko: "취소", en: "Cancel"
        )
        public static let confirm = LocalizedKey(
            key: "common.confirm", ko: "확인", en: "OK"
        )
        public static let retry = LocalizedKey(
            key: "common.retry", ko: "다시 시도", en: "Retry"
        )
    }

    /// 모든 키 enumeration — 테스트가 ko/en 비어있는지 + 중복 검증.
    public static var allKeys: [LocalizedKey] {
        [
            App.title,
            Onboarding.welcomeTitle, Onboarding.detectAgentsTitle, Onboarding.firstFolderTitle,
            Onboarding.skip, Onboarding.next, Onboarding.start, Onboarding.back, Onboarding.addFolder,
            Menu.newFolder, Menu.revealDataFolder, Menu.exportDiagnostics,
            Menu.removeSelectedFolder, Menu.preferences, Menu.commandPalette, Menu.help,
            Preferences.title, Preferences.general, Preferences.agents,
            Preferences.shortcuts, Preferences.advanced, Preferences.notifications, Preferences.openInFinder,
            Inbox.empty, Inbox.unreadCount,
            Common.cancel, Common.confirm, Common.retry,
        ]
    }
}
