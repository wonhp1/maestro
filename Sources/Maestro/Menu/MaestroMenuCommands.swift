import MaestroCore
import SwiftUI

/// 표준 macOS 메뉴 — File / Edit / Maestro / Window / Help.
///
/// 각 액션은 `MenuActionRouter` 에 위임 — 호스트가 실제 핸들러 등록.
/// SwiftUI 가 `Commands` 를 view body 에 주입하므로 별도 ViewModel 없이 직접 구성.
struct MaestroMenuCommands: Commands {
    let router: MenuActionRouter

    var body: some Commands {
        // File 메뉴 — 새 폴더 / 데이터 폴더 열기 / 진단 번들
        CommandGroup(after: .newItem) {
            Button("새 폴더 추가…") { router.addFolder() }
                .keyboardShortcut("n", modifiers: [.command])
            Divider()
            Button("데이터 폴더 열기") { router.revealDataFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("진단 번들 내보내기…") { router.exportDiagnostics() }
        }

        // Edit 메뉴 — 선택 폴더 제거
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("선택 폴더 제거") { router.deleteSelectedFolder() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!router.canDeleteSelectedFolder)
        }

        // Maestro 메뉴 (앱 메뉴) — 환경설정
        CommandGroup(replacing: .appSettings) {
            Button("환경설정…") { router.openPreferences() }
                .keyboardShortcut(",", modifiers: [.command])
        }

        // Window — 커맨드 팔레트 열기 (Cmd+K 는 ControlTowerView 도 등록, 메뉴는 발견성)
        CommandGroup(after: .windowList) {
            Divider()
            Button("커맨드 팔레트") { router.openCommandPalette() }
                .keyboardShortcut("k", modifiers: [.command])
        }

        // Help
        CommandGroup(replacing: .help) {
            Button("Maestro 도움말") { router.openHelp() }
        }
    }
}
