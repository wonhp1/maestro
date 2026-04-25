import MaestroCore
import SwiftUI

/// Maestro 앱의 진입점.
///
/// Scene 구성:
/// - 메인 윈도우: 컨트롤 타워 (`ContentView`).
/// - 메뉴바 트레이: `MaestroMenuBarExtra` (활동 요약 + 자주 쓰는 액션).
/// - macOS 표준 메뉴: `MaestroMenuCommands` (File / Edit / Maestro / Window / Help).
///
/// `ControlTowerEnvironment` 한 인스턴스를 두 Scene 이 공유 — `@State` 로 한 번 만들면
/// 앱 수명 유지.
@main
struct MaestroApp: App {
    @State private var environment = ControlTowerEnvironment.makeProduction()

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
            MaestroMenuCommands(router: environment.menuActionRouter)
        }

        MaestroMenuBarExtra(
            summary: environment.activitySummary,
            router: environment.menuActionRouter
        )
    }
}
