import MaestroAdapters
import MaestroCore
import SwiftUI

/// 컨트롤 타워 메인 뷰 — 3-컬럼 NavigationSplitView.
///
/// 구조:
/// ```
/// VStack
/// ├── OrchestrationStatusBar (있을 때만)
/// └── NavigationSplitView
///     ├── Sidebar: SidebarView (folders + status badges)
///     ├── Detail: 선택 폴더의 ChatView (ChatSessionStore 가 캐시)
///     └── Inspector: InboxPanel
/// ```
struct ControlTowerView: View {
    @Bindable var environment: ControlTowerEnvironment

    var body: some View {
        NavigationSplitView {
            if let viewModel = environment.folderViewModel {
                SidebarView(
                    viewModel: viewModel,
                    statusStore: environment.statusStore,
                    inboxStore: environment.inboxStore
                )
            } else {
                ProgressView("초기화 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } content: {
            detailContent
                // status bar 를 detail safe-area 상단에 고정 — VStack 외부 reflow 방지
                // (must-fix B2). 빈 상태에서도 레이아웃 jump 없음.
                .safeAreaInset(edge: .top, spacing: 0) {
                    OrchestrationStatusBar(model: environment.orchestrationStatus)
                }
        } detail: {
            InboxPanel(
                store: environment.inboxStore,
                selectedFolderID: environment.folderViewModel?.selectedFolderID,
                folderTitleResolver: { id in
                    environment.folderViewModel?.folders
                        .first(where: { $0.id == id })?.displayName
                        ?? id.rawValue
                }
            )
        }
        .task {
            await environment.bootstrap()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let viewModel = environment.folderViewModel,
           let id = viewModel.selectedFolderID,
           let folder = viewModel.folders.first(where: { $0.id == id }) {
            if let chatViewModel = environment.chatSessionStore.cached(for: id) {
                ChatView(viewModel: chatViewModel)
            } else if environment.chatSessionStore.loadingFolderIDs.contains(id) {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("채팅 세션 준비 중…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = environment.chatSessionStore.lastErrors[id] {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                    Text("세션 생성 실패")
                        .font(.headline)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("다시 시도") {
                        Task { await environment.chatSessionStore.ensureSession(for: folder) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                // ensureSession 을 트리거 — `task(id:)` 로 폴더 변경 시 이전 호출 cancel.
                // Color.clear race (must-fix A4) 회피: 안정 identity 부여.
                Color.clear
                    .task(id: folder.id) {
                        await environment.chatSessionStore.ensureSession(for: folder)
                    }
            }
        } else if environment.folderViewModel?.folders.isEmpty == true {
            placeholder(
                icon: "folder.badge.plus",
                title: "폴더를 추가하세요",
                subtitle: "사이드바의 '+ 폴더 추가' 버튼으로 작업 폴더를 등록할 수 있습니다."
            )
        } else {
            placeholder(
                icon: "sidebar.left",
                title: "폴더를 선택하세요",
                subtitle: "왼쪽에서 폴더를 선택하면 채팅이 시작됩니다."
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

/// 컨트롤 타워의 모든 store 와 의존성을 묶은 composition root.
///
/// `ContentView` 가 한 인스턴스를 만들어 ControlTowerView 에 주입.
@MainActor
@Observable
public final class ControlTowerEnvironment {
    public let statusStore: AgentStatusStore
    public let inboxStore: InboxStore
    public let orchestrationStatus: OrchestrationStatusModel
    public let chatSessionStore: ChatSessionStore
    public private(set) var folderViewModel: FolderViewModel?

    @ObservationIgnored
    private let pathsProvider: () throws -> AppSupportPaths
    @ObservationIgnored
    private let pickerFactory: @MainActor () -> FolderPicking

    public init(
        pathsProvider: @escaping () throws -> AppSupportPaths,
        pickerFactory: @escaping @MainActor () -> FolderPicking,
        chatViewModelFactory: @escaping @MainActor (FolderRegistration) async throws
            -> ChatViewModel,
        statusStore: AgentStatusStore = AgentStatusStore(),
        inboxStore: InboxStore = InboxStore(),
        orchestrationStatus: OrchestrationStatusModel = OrchestrationStatusModel()
    ) {
        self.pathsProvider = pathsProvider
        self.pickerFactory = pickerFactory
        self.statusStore = statusStore
        self.inboxStore = inboxStore
        self.orchestrationStatus = orchestrationStatus
        // ChatSessionStore 를 init 에서 직접 초기화 — IUO 제거 (must-fix A1).
        self.chatSessionStore = ChatSessionStore(
            factory: chatViewModelFactory,
            statusStore: statusStore
        )
    }

    /// production 기본 환경 — NSOpenPanelFolderPicker + MockAdapter (Phase 13 에서 실제 어댑터 wiring).
    public static func makeProduction() -> ControlTowerEnvironment {
        ControlTowerEnvironment(
            pathsProvider: { try AppSupportPaths.forApplication() },
            pickerFactory: { NSOpenPanelFolderPicker() },
            chatViewModelFactory: { folder in
                let adapter = MockAdapter()
                let session = try await adapter.createSession(folderPath: folder.path)
                return try ChatViewModel(adapter: adapter, session: session)
            }
        )
    }

    public func bootstrap() async {
        guard folderViewModel == nil else { return }
        do {
            let paths = try pathsProvider()
            try paths.ensureAllDirectoriesExist()
            let registry = FolderRegistry(paths: paths)
            let viewModel = FolderViewModel(
                registry: registry,
                picker: pickerFactory(),
                defaultAdapterID: AdapterID(rawValue: "claude")
            )
            self.folderViewModel = viewModel
            await viewModel.bootstrap()
        } catch {
            self.folderViewModel = nil
        }
    }
}
