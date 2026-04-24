import MaestroCore
import SwiftUI

/// Maestro 앱의 진입점.
///
/// - Scene 구성은 의도적으로 최소 — `MaestroConfig` 의 상수로 윈도우 크기/타이틀을 주입.
/// - Phase 12 에서 여기서 Scene 구성이 컨트롤 타워 + 설정 윈도우 분리로 확장됨.
@main
struct MaestroApp: App {
    var body: some Scene {
        WindowGroup(
            String(localized: String.LocalizationValue(MaestroConfig.defaultWindowTitleKey))
        ) {
            ContentView()
                .frame(
                    minWidth: MaestroConfig.minimumWindowSize.width,
                    idealWidth: MaestroConfig.defaultWindowSize.width,
                    minHeight: MaestroConfig.minimumWindowSize.height,
                    idealHeight: MaestroConfig.defaultWindowSize.height
                )
        }
        .windowResizability(.contentMinSize)
    }
}
