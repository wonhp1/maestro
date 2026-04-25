import MaestroAdapters
import MaestroCore
import SwiftUI

/// Phase 8 — 단일 ChatView (MockAdapter) 호스팅.
/// Phase 12 에서 컨트롤 타워 + 다중 어댑터 선택 UI 로 확장.
struct ContentView: View {
    @State private var loaded: LoadedChat?

    var body: some View {
        Group {
            if let loaded {
                ChatView(viewModel: loaded.viewModel)
            } else {
                bootstrap
            }
        }
        .task {
            if loaded == nil {
                loaded = await LoadedChat.makeDefault()
            }
        }
    }

    private var bootstrap: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Initializing chat…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 어댑터 + 세션 + ViewModel 의 한 묶음 — `@State` 호환.
@MainActor
private final class LoadedChat {
    let viewModel: ChatViewModel
    init(viewModel: ChatViewModel) { self.viewModel = viewModel }

    /// 기본 환경 — MockAdapter (Claude 가용성과 무관하게 UI 검증 가능).
    static func makeDefault() async -> LoadedChat? {
        do {
            let adapter = MockAdapter()
            let session = try await adapter.createSession(
                folderPath: FileManager.default.homeDirectoryForCurrentUser
            )
            let viewModel = try ChatViewModel(adapter: adapter, session: session)
            return LoadedChat(viewModel: viewModel)
        } catch {
            return nil
        }
    }
}

#Preview {
    ContentView()
}
