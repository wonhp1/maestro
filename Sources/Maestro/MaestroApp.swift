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

    /// PATH 머지 결과를 OSLog `process` 로 기록 + **디버그 파일** 기록.
    /// 파일: `~/Library/Logs/Maestro/path-augment.log` — OSLog `<private>` 마스킹
    /// 회피용. 매 실행마다 append. v0.4.4 안정화 후 제거 예정.
    private static func logAugmentResult(_ result: AugmentResult) {
        let logger = MaestroLogger(category: .process)
        let summary: String
        switch result {
        case .augmented(let added):
            summary = "augmented: +\(added) entries"
            logger.publicInfo("PATH augmented from login shell")
        case .alreadyAugmented:
            summary = "alreadyAugmented (no-op)"
            logger.publicInfo("PATH already augmented")
        case .extractFailed(let error):
            summary = "extractFailed: \(String(describing: error))"
            logger.publicInfo("PATH extract failed")
        case .setenvFailed(let errno):
            summary = "setenvFailed errno=\(errno)"
            logger.publicInfo("PATH setenv failed")
        }
        let pathSnapshot = ProcessInfo.processInfo.environment["PATH"] ?? "(nil)"
        let line = """
            === \(Date()) ===
            result: \(summary)
            HOME: \(FileManager.default.homeDirectoryForCurrentUser.path)
            SHELL env: \(ProcessInfo.processInfo.environment["SHELL"] ?? "(unset)")
            PATH after augment:
            \(pathSnapshot.split(separator: ":").map { "  \($0)" }.joined(separator: "\n"))
            ===\n
            """
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/Maestro", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: logsDir, withIntermediateDirectories: true
        )
        let logFile = logsDir.appending(path: "path-augment.log", directoryHint: .notDirectory)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path),
               let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    var body: some Scene {
        // I-01 fix — String Catalog 미도입 상태에서 LocalizationValue("window.main.title")
        // 가 키를 그대로 표시하던 버그. literal "Maestro" 로 폴백 (Phase 22 의 정식 다국어
        // 카탈로그 진입 시 다시 localized 화).
        WindowGroup("Maestro") {
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
