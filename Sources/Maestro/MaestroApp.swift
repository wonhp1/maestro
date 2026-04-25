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
        //
        // **순수 동기** — `Task.detached` + `DispatchSemaphore` 는 SwiftUI `@main App
        // init()` 컨텍스트에서 cooperative pool 스케줄링과 충돌할 수 있어 (v0.4.3 에서
        // 실제로 augmentation 이 일어나지 않는 footgun 발견). spawn + waitUntilExit
        // 으로 직접 처리.
        let result = EnvironmentAugmenter.augmentPATHFromLoginShellSync()
        Self.logAugmentResult(result)
        _environment = State(wrappedValue: ControlTowerEnvironment.makeProduction())
    }

    /// PATH 머지 결과를 OSLog 카테고리 `process` 로 기록 — Console.app 에서
    /// `subsystem:com.gimgyeongwon.maestro category:process` 필터로 확인 가능.
    private static func logAugmentResult(_ result: AugmentResult) {
        let logger = MaestroLogger(category: .process)
        switch result {
        case .augmented(let added):
            logger.info("PATH augmented: +\(added) entries from login shell")
        case .alreadyAugmented:
            logger.info("PATH already augmented (no-op)")
        case .extractFailed(let error):
            logger.error("PATH extract failed: \(String(describing: error))")
        case .setenvFailed(let errno):
            logger.error("PATH setenv failed: errno=\(errno)")
        }
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
                onExportDiagnostics: {
                    await DiagnosticsExporter.exportInteractive(paths: paths)
                },
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
