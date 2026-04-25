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
    @State private var environment: ControlTowerEnvironment
    @State private var updateController = UpdateController()

    init() {
        // .app launch 시 PATH 보정: 사용자 로그인 쉘의 PATH 를 머지해서
        // ~/.npm-global/bin, /opt/homebrew/bin 등 사용자 설치 CLI 가 발견되도록 함.
        // **동기 대기 필요** — ControlTowerEnvironment.makeProduction() 이 CLI 감지를
        // 시작하므로 PATH 가 먼저 setenv 되어야 race 가 없음.
        // 1500ms 안에 못 끝내면 그냥 진행 — 사용자 ~/.zshrc 가 nvm/conda 등으로 무거운
        // 케이스 대비. macOS app-launch hang 임계 (~4s) 의 1/3 만 점유.
        // Extractor 자체 timeout 은 1.2s 로 살짝 더 짧게 설정 — semaphore wait 가 항상
        // ProcessExecutor timeout 보다 길도록.
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            _ = await EnvironmentAugmenter.augmentPATHFromLoginShell(
                extractor: LoginShellPathExtractor(timeout: 1.2)
            )
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + .milliseconds(1500))
        _environment = State(wrappedValue: ControlTowerEnvironment.makeProduction())
    }

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
