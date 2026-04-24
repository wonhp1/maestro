import MaestroCore
import SwiftUI

/// Phase 1 플레이스홀더. 후속 Phase에서 컨트롤 타워 레이아웃(P12)으로 대체된다.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🎼")
                .font(.system(size: 64))
            Text(MaestroConfig.appName)
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("v\(MaestroConfig.appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("AI 코딩 에이전트 공용 지휘소")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
