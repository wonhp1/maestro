import MaestroCore
import SwiftUI

/// Maestro 앱의 진입점.
///
/// Scene 구성:
/// - 메인 윈도우: 컨트롤 타워 (`ContentView`).
/// - 메뉴바 트레이: `MaestroMenuBarExtra` (활동 요약 + 자주 쓰는 액션).
/// - 환경설정 윈도우: `Settings { MaestroSettingsRoot(...) }` — 표준 ⌘, 트리거.
/// - macOS 표준 메뉴: `MaestroMenuCommands` (File / Edit / Maestro / Window / Help).
///
/// `ControlTowerEnvironment` 한 인스턴스를 모든 Scene 이 공유 — `@State` 로 한 번 만들면
/// 앱 수명 유지.
@main
struct MaestroApp: App {
    @State private var environment = ControlTowerEnvironment.makeProduction()
    @State private var updateController = UpdateController()

    var body: some Scene {
        WindowGroup(
            String(localized: String.LocalizationValue(MaestroConfig.defaultWindowTitleKey))
        ) {
            ContentView(environment: environment)
                .frame(
                    minWidth: MaestroConfig.minimumWindowSize.width,
                    idealWidth: MaestroConfig.defaultWindowSize.width,
                    minHeight: MaestroConfig.minimumWindowSize.height,
                    idealHeight: MaestroConfig.defaultWindowSize.height
                )
        }
        .windowResizability(.contentMinSize)
        .commands {
            MaestroMenuCommands(
                router: environment.menuActionRouter,
                updateController: updateController
            )
        }

        Settings {
            MaestroSettingsRoot(environment: environment)
        }

        MaestroMenuBarExtra(
            summary: environment.activitySummary,
            router: environment.menuActionRouter
        )
    }
}

/// `Settings` Scene 의 root — `preferencesStore` 가 bootstrap 후 set 되는 점 처리.
private struct MaestroSettingsRoot: View {
    @Bindable var environment: ControlTowerEnvironment

    var body: some View {
        if let prefs = environment.preferencesStore,
           let paths = environment.resolvedPaths {
            PreferencesView(
                preferences: prefs,
                apiKeyStorage: environment.apiKeyStorage,
                dataFolderURL: paths.root,
                onExportDiagnostics: { /* Phase 22 */ },
                onRequestNotificationPermission: {
                    _ = await environment.notificationService.requestAuthorization()
                }
            )
        } else {
            ProgressView("초기화 중…")
                .frame(width: 400, height: 200)
        }
    }
}
