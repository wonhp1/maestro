import AppKit
import MaestroCore

/// `AppActivitySummary.dockBadgeLabel` 변화를 1초 주기로 읽어 `NSApp.dockTile.badgeLabel`
/// 동기화. 값이 동일하면 set 생략 — 시스템 호출 비용 최소화.
///
/// observation 기반 push 대신 1s polling — Phase 18 의 dock 뱃지는 실시간성이
/// 중요하지 않고, observation tracking 의 single-fire 한계를 우회하기 위함.
@MainActor
public final class DockBadgeUpdater {
    private let summary: AppActivitySummary
    private var task: Task<Void, Never>?
    private var lastLabel: String?

    public init(summary: AppActivitySummary) {
        self.summary = summary
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.driveLoop()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        NSApp.dockTile.badgeLabel = nil
    }

    private func driveLoop() async {
        while !Task.isCancelled {
            let next = summary.dockBadgeLabel
            if next != lastLabel {
                NSApp.dockTile.badgeLabel = next
                lastLabel = next
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
