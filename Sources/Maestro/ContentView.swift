import MaestroAdapters
import MaestroCore
import SwiftUI

/// Phase 12 — 컨트롤 타워 진입점.
///
/// `MaestroApp` 가 `ControlTowerEnvironment.makeProduction()` 한 인스턴스를 만들어
/// 메인 윈도우 + 메뉴바 트레이가 공유.
struct ContentView: View {
    @Bindable var environment: ControlTowerEnvironment

    var body: some View {
        ControlTowerView(environment: environment)
    }
}
