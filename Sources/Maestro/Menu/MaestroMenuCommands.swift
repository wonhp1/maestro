import MaestroCore
import SwiftUI

/// 표준 macOS 메뉴 — File / Edit / Maestro / Window / Help.
///
/// 각 액션은 `MenuActionRouter` 에 위임 — 호스트가 실제 핸들러 등록.
/// SwiftUI 가 `Commands` 를 view body 에 주입하므로 별도 ViewModel 없이 직접 구성.
struct MaestroMenuCommands: Commands {
    let router: MenuActionRouter
    let updateController: UpdateController

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

        // Maestro 앱 메뉴 — 업데이트 확인. 환경설정 항목은 SwiftUI 가 Settings scene
        // 등록 시 자동 생성 (현재 시스템 언어 따라 "환경설정..." / "Settings..." 자동
        // 번역, ⌘, 단축키 자동 wire). v0.4.6 까지는 .appSettings 를 replacing 으로
        // 덮어 NSApp.sendAction(showSettingsWindow:) 로 invoke 했는데 SwiftUI 가
        // 그 selector 를 일관되게 처리하지 않아 Settings 창이 안 열리는 버그 (I-06).
        // v0.4.7 에서 표준 자동 항목 사용으로 회귀 — 동시에 메뉴 중복 (I-07) 해결.
        CommandGroup(after: .appInfo) {
            Button("업데이트 확인…") { updateController.checkForUpdates() }
                .disabled(!updateController.canCheckForUpdates)
        }

        // Window — 커맨드 팔레트 + 폴더 인덱스 전환 (⌘1~⌘9)
        // I-05 fix: ⌘1~⌘9 는 ControlTowerView 의 hidden background Button 으로는
        // NavigationSplitView focus 때문에 키 입력 안 받음. menu Commands 로 옮김.
        CommandGroup(after: .windowList) {
            Divider()
            Button("커맨드 팔레트") { router.openCommandPalette() }
                .keyboardShortcut("k", modifiers: [.command])
            Divider()
            ForEach(1...9, id: \.self) { index in
                Button("폴더 \(index) 전환") { router.selectFolder(at: index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [.command])
            }
        }

        // Help
        CommandGroup(replacing: .help) {
            Button("Maestro 도움말") { router.openHelp() }
            Divider()
            Button("피드백 보내기…") { router.sendFeedback() }
        }
    }
}
