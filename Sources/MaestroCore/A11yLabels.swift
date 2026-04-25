import Foundation

/// 접근성(VoiceOver) 라벨 / 힌트의 중앙 카탈로그.
///
/// SwiftUI view 가 `.accessibilityLabel(A11yLabels.X.label.localized())` 형식으로
/// 사용. LocalizationKeys 와 같은 (ko, en) 패턴 + 별도 `hint` 도 옵션으로.
///
/// `LocalizedKey` 그대로 재사용 — 테스트가 모든 a11y 라벨 빠짐없이 ko/en 검증.
public enum A11yLabels {
    public enum Folder {
        public static let addButton = LocalizedKey(
            key: "a11y.folder.addButton",
            ko: "새 작업 폴더 추가",
            en: "Add a new working folder"
        )
        public static let removeButton = LocalizedKey(
            key: "a11y.folder.removeButton",
            ko: "선택된 폴더 제거",
            en: "Remove the selected folder"
        )
        public static let switchHint = LocalizedKey(
            key: "a11y.folder.switchHint",
            ko: "이 폴더로 전환합니다",
            en: "Switches to this folder"
        )
    }

    public enum Dispatch {
        public static let composer = LocalizedKey(
            key: "a11y.dispatch.composer",
            ko: "메시지 입력란",
            en: "Message composer"
        )
        public static let sendButton = LocalizedKey(
            key: "a11y.dispatch.send",
            ko: "메시지 전송",
            en: "Send message"
        )
        public static let sendHint = LocalizedKey(
            key: "a11y.dispatch.sendHint",
            ko: "현재 폴더의 에이전트로 메시지를 전송합니다",
            en: "Sends the message to the current folder's agent"
        )
    }

    public enum Inbox {
        public static let panel = LocalizedKey(
            key: "a11y.inbox.panel",
            ko: "받은 메시지 목록",
            en: "Inbox messages list"
        )
        public static let item = LocalizedKey(
            key: "a11y.inbox.item",
            ko: "받은 메시지",
            en: "Inbox message"
        )
    }

    public enum CommandPalette {
        public static let searchField = LocalizedKey(
            key: "a11y.palette.search",
            ko: "커맨드 팔레트 검색",
            en: "Command palette search"
        )
        public static let resultList = LocalizedKey(
            key: "a11y.palette.results",
            ko: "검색 결과 목록",
            en: "Search results list"
        )
    }

    public enum MenuBar {
        public static let trayIcon = LocalizedKey(
            key: "a11y.menubar.tray",
            ko: "Maestro 메뉴바 트레이",
            en: "Maestro menu bar tray"
        )
        public static let summary = LocalizedKey(
            key: "a11y.menubar.summary",
            ko: "활동 요약",
            en: "Activity summary"
        )
    }

    public static var allLabels: [LocalizedKey] {
        [
            Folder.addButton, Folder.removeButton, Folder.switchHint,
            Dispatch.composer, Dispatch.sendButton, Dispatch.sendHint,
            Inbox.panel, Inbox.item,
            CommandPalette.searchField, CommandPalette.resultList,
            MenuBar.trayIcon, MenuBar.summary,
        ]
    }
}
