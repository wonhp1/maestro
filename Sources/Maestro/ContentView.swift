import MaestroAdapters
import MaestroCore
import SwiftUI

/// Phase 10 — 폴더 사이드바 + 메인 채팅 패널 (NavigationSplitView).
///
/// 구조:
/// ```
/// NavigationSplitView
/// ├── Sidebar: SidebarView(folders + 추가 버튼)
/// └── Detail: 선택 폴더의 ChatView (없으면 안내)
/// ```
///
/// 어댑터는 폴더의 `adapterId` 에 따라 `AdapterRegistry` 에서 lookup.
/// 폴더가 바뀔 때마다 `ChatViewModel` 을 재생성 (캐싱은 Phase 12 의 ChatSessionStore 에서).
struct ContentView: View {
    @State private var environment = AppEnvironment()

    var body: some View {
        NavigationSplitView {
            if let folderViewModel = environment.folderViewModel {
                SidebarView(viewModel: folderViewModel)
            } else {
                ProgressView("초기화 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } detail: {
            detailContent
        }
        .task {
            await environment.bootstrap()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let chatViewModel = environment.activeChatViewModel {
            ChatView(viewModel: chatViewModel)
        } else if let id = environment.folderViewModel?.selectedFolderID,
                  environment.folderViewModel?.folders.contains(where: { $0.id == id }) == true {
            // 폴더는 선택됐지만 ChatViewModel 이 아직 생성 중 — loading state.
            VStack(spacing: 12) {
                ProgressView()
                Text("채팅 세션 준비 중…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if environment.folderViewModel?.folders.isEmpty == true {
            placeholder(
                icon: "folder.badge.plus",
                title: "폴더를 추가하세요",
                subtitle: "왼쪽 사이드바의 '+ 폴더 추가' 버튼으로 작업 폴더를 등록할 수 있습니다."
            )
        } else {
            placeholder(
                icon: "sidebar.left",
                title: "폴더를 선택하세요",
                subtitle: "왼쪽 사이드바에서 폴더를 클릭하면 채팅이 시작됩니다."
            )
        }
    }

    private func placeholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 앱 전역 — 폴더 레지스트리 + ViewModel + 활성 chat session 관리.
///
/// `@Observable` 으로 ContentView 가 `activeChatViewModel` 변화에 자동 반응.
@MainActor
@Observable
final class AppEnvironment {
    private(set) var folderViewModel: FolderViewModel?
    private(set) var activeChatViewModel: ChatViewModel?

    @ObservationIgnored
    private var lastSelectedFolderID: FolderID?

    func bootstrap() async {
        guard folderViewModel == nil else { return }
        do {
            let paths = try AppSupportPaths.forApplication()
            try paths.ensureAllDirectoriesExist()
            let registry = FolderRegistry(paths: paths)
            let picker = NSOpenPanelFolderPicker()
            let viewModel = FolderViewModel(
                registry: registry,
                picker: picker,
                defaultAdapterID: AdapterID(rawValue: "claude")
            )
            self.folderViewModel = viewModel
            await viewModel.bootstrap()
            observeSelection(viewModel: viewModel)
        } catch {
            // bootstrap 실패 시 — UI 가 placeholder 만 표시. 향후 Phase 19 의 진단 화면으로 surface.
            self.folderViewModel = nil
        }
    }

    /// Observation 기반 selection 감시 — 200ms polling 제거 (UX/Arch must-fix).
    /// `withObservationTracking` 가 selectedFolderID 변경 시 onChange 한 번 호출 →
    /// 재armed. 변경 없으면 idle.
    private func observeSelection(viewModel: FolderViewModel) {
        withObservationTracking {
            _ = viewModel.selectedFolderID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.reconcileSelection(viewModel: viewModel)
                self.observeSelection(viewModel: viewModel)
            }
        }
    }

    private func reconcileSelection(viewModel: FolderViewModel) async {
        let currentID = viewModel.selectedFolderID
        guard currentID != lastSelectedFolderID else { return }
        lastSelectedFolderID = currentID
        guard let id = currentID,
              let folder = viewModel.folders.first(where: { $0.id == id }) else {
            activeChatViewModel = nil
            return
        }
        activeChatViewModel = await makeChatViewModel(for: folder)
    }

    /// 선택된 폴더에 대해 ChatViewModel 생성.
    /// Phase 10 범위: MockAdapter 만 — 실제 어댑터 lookup 은 Phase 11+ 에서 AdapterRegistry 와 통합.
    private func makeChatViewModel(for folder: FolderRegistration) async -> ChatViewModel? {
        do {
            let adapter = MockAdapter()
            let session = try await adapter.createSession(folderPath: folder.path)
            return try ChatViewModel(adapter: adapter, session: session)
        } catch {
            return nil
        }
    }
}

#Preview {
    ContentView()
}
