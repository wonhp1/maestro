import SwiftUI
import MaestroCore

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
