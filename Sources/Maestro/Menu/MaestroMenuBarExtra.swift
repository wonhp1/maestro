import MaestroCore
import SwiftUI

/// 메뉴바 상단 트레이 아이콘 — 앱 창을 열지 않고도 활동 요약을 확인.
///
/// SwiftUI `MenuBarExtra` Scene — 클릭 시 popover 가 활동 요약 + 자주 쓰는 액션 노출.
struct MaestroMenuBarExtra: Scene {
    let summary: AppActivitySummary
    let router: MenuActionRouter

    var body: some Scene {
        MenuBarExtra("Maestro", systemImage: iconName) {
            MaestroMenuBarContent(summary: summary, router: router)
        }
        .menuBarExtraStyle(.menu)
    }

    private var iconName: String {
        summary.runningDispatchCount > 0
            ? "circle.dotted.circle"
            : "music.quarternote.3"
    }
}

private struct MaestroMenuBarContent: View {
    @Bindable var summary: AppActivitySummary
    let router: MenuActionRouter

    var body: some View {
        Text(summary.menuBarSummaryLine)

        Divider()

        Button("새 폴더 추가…") { router.addFolder() }
        Button("커맨드 팔레트 열기") { router.openCommandPalette() }
        Button("데이터 폴더 열기") { router.revealDataFolder() }

        Divider()

        Button("환경설정…") { router.openPreferences() }
            .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("Maestro 종료") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
