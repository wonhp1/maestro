import Foundation
import Observation

/// 메뉴바 / Dock 뱃지 / 알림이 한 번에 읽는 앱 전역 활동 요약.
///
/// 다른 store 들이 직접 변경 (push). 이 모델은 단순한 보관함 — derive 로직 (filter)
/// 은 caller (ControlTowerEnvironment 의 wiring 함수) 가 책임.
///
/// ## 멤버
/// - `runningDispatchCount`: OrchestrationStatusModel 의 `.running` entry 수
/// - `unreadInboxCount`: InboxStore 의 `totalUnread`
/// - `folderCount`: FolderViewModel.folders.count
/// - `lastInboxArrival`: 가장 최근 inbox 도착 시각
@MainActor
@Observable
public final class AppActivitySummary {
    public var runningDispatchCount: Int = 0
    public var unreadInboxCount: Int = 0
    public var folderCount: Int = 0
    public var lastInboxArrival: Date?

    public init() {}

    /// 메뉴바 / Dock 뱃지에 표시할 짧은 라벨. 0 이면 nil.
    public var dockBadgeLabel: String? {
        let total = runningDispatchCount + unreadInboxCount
        return total > 0 ? "\(total)" : nil
    }

    /// "에이전트 3 · 진행 1 · 미확인 2" 형식.
    public var menuBarSummaryLine: String {
        var parts: [String] = []
        parts.append("에이전트 \(folderCount)")
        if runningDispatchCount > 0 { parts.append("진행 \(runningDispatchCount)") }
        if unreadInboxCount > 0 { parts.append("미확인 \(unreadInboxCount)") }
        return parts.joined(separator: " · ")
    }

    public var hasAnyActivity: Bool {
        runningDispatchCount > 0 || unreadInboxCount > 0
    }
}
