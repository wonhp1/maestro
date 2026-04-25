import MaestroAdapters
import MaestroCore
import SwiftUI

/// Phase 12 — 컨트롤 타워 진입점.
///
/// `ControlTowerEnvironment.makeProduction()` 가 모든 store 와 의존성을 묶어서
/// `ControlTowerView` 로 주입. 별도의 wiring 코드가 ContentView 에 남지 않음.
struct ContentView: View {
    @State private var environment = ControlTowerEnvironment.makeProduction()

    var body: some View {
        ControlTowerView(environment: environment)
    }
}

#Preview {
    ContentView()
}
