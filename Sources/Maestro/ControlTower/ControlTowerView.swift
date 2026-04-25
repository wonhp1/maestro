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
                .safeAreaInset(edge: .top, spacing: 0) {
                    OrchestrationStatusBar(model: environment.orchestrationStatus)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let folderViewModel = environment.folderViewModel,
                       !folderViewModel.folders.isEmpty {
                        DispatchComposer(folderViewModel: folderViewModel) { folder, body in
                            await environment.sendDispatch(to: folder, body: body)
                        }
                    }
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
        // Cmd+K — 커맨드 팔레트 열기
        .background(
            Button("") {
                Task { await environment.commandPaletteViewModel.present() }
            }
            .keyboardShortcut("k", modifiers: [.command])
            .opacity(0)
            .frame(width: 0, height: 0)
        )
        // 폴더 단축키 ⌘1 ~ ⌘9
        .background(folderShortcuts)
        .sheet(isPresented: Bindable(environment.commandPaletteViewModel).isPresented) {
            CommandPaletteView(viewModel: environment.commandPaletteViewModel)
        }
    }

    @ViewBuilder
    private var folderShortcuts: some View {
        if let folderViewModel = environment.folderViewModel {
            ForEach(Array(folderViewModel.folders.prefix(9).enumerated()), id: \.element.id) { idx, folder in
                Button("") {
                    Task { await folderViewModel.select(id: folder.id) }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
            }
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
    public let commandRegistry: CommandRegistry
    public let recentCommandTracker: RecentCommandTracker
    public let commandPaletteViewModel: CommandPaletteViewModel
    public private(set) var folderViewModel: FolderViewModel?
    public private(set) var dispatchService: DispatchService?

    @ObservationIgnored
    private let pathsProvider: () throws -> AppSupportPaths
    @ObservationIgnored
    private let pickerFactory: @MainActor () -> FolderPicking
    @ObservationIgnored
    private let envelopeStorage: EnvelopeStorage = EnvelopeStorage()

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
        self.chatSessionStore = ChatSessionStore(
            factory: chatViewModelFactory,
            statusStore: statusStore
        )
        let registry = CommandRegistry()
        let tracker = RecentCommandTracker()
        self.commandRegistry = registry
        self.recentCommandTracker = tracker
        self.commandPaletteViewModel = CommandPaletteViewModel(
            registry: registry, recentTracker: tracker
        )
    }

    /// production 기본 환경 — NSOpenPanelFolderPicker + MockAdapter (Phase 14+ 에서 실제 어댑터 wiring).
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

    /// UI 의 "보내기" 액션을 DispatchService 로 전달.
    /// dispatch 시작 전에 ChatSessionStore 가 해당 폴더의 세션을 ensure 함 — 첫 dispatch 도 동작.
    public func sendDispatch(to folder: FolderRegistration, body: String) async {
        _ = await chatSessionStore.ensureSession(for: folder)
        guard let dispatchService else { return }
        let from = AgentID(rawValue: "control")
        let to = ControlTowerEnvironment.syntheticAgentID(for: folder.id)
        do {
            _ = try await dispatchService.dispatch(
                from: from, to: to, body: body, expectReply: true
            )
        } catch {
            // observer 가 statusStore 에 error 기록 — UI 가 자동 surface.
        }
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
            await wireDispatchService(paths: paths, folderViewModel: viewModel)
            await commandRegistry.register(
                FolderCommandProvider(folderViewModel: viewModel),
                id: "folder"
            )
        } catch {
            self.folderViewModel = nil
        }
    }

    /// DispatchService 를 wiring — Phase 13.
    /// 합성 AgentID = "folder-<id.rawValue>" — Phase 14+ 에서 FolderRegistration.agentId 도입 시 교체.
    private func wireDispatchService(
        paths: AppSupportPaths,
        folderViewModel: FolderViewModel
    ) async {
        let logger = ThreadLogger(paths: paths)
        let resolver = ChatSessionAgentResolver(
            sessionStore: chatSessionStore,
            folderViewModel: folderViewModel
        )
        let router = EnvelopeRouter(
            paths: paths,
            storage: envelopeStorage,
            logger: logger,
            resolver: resolver
        )
        let observer = ControlTowerDispatchObserver(
            orchestrationStatus: orchestrationStatus,
            agentStatus: statusStore,
            inbox: inboxStore,
            agentToFolder: { [weak folderViewModel] agentID in
                guard let folderViewModel else { return nil }
                return await MainActor.run {
                    folderViewModel.folders.first { folder in
                        Maestro.syntheticAgentID(for: folder.id) == agentID
                    }?.id
                }
            }
        )
        self.dispatchService = DispatchService(
            router: router,
            resolver: resolver,
            observer: observer
        )
    }
}

/// 폴더에 대한 합성 AgentID 생성.
/// FolderID rawValue 가 UUID 형식 — Identifier.validated 통과 보장.
/// nonisolated — closure 에서 자유롭게 호출 가능.
func syntheticAgentID(for folderID: FolderID) -> AgentID {
    let raw = "agent-\(folderID.rawValue.lowercased())"
    return (try? AgentID.validated(rawValue: raw)) ?? AgentID(rawValue: raw)
}

extension ControlTowerEnvironment {
    /// 외부 노출 wrapper — 같은 매핑.
    public static func syntheticAgentID(for folderID: FolderID) -> AgentID {
        Maestro.syntheticAgentID(for: folderID)
    }
}

/// `AgentResolving` production — ChatSessionStore 의 캐시된 ChatViewModel 에서 어댑터/세션 회수.
/// **자동 ensureSession** — 캐시 miss 시 세션 생성. 한 번도 열지 않은 폴더에 대한
/// 릴레이 dispatch 가 silently DLQ 로 가는 것 방어 (must-fix HIGH-4).
@MainActor
private final class ChatSessionAgentResolver: AgentResolving {
    private let sessionStore: ChatSessionStore
    private let folderViewModel: FolderViewModel

    init(sessionStore: ChatSessionStore, folderViewModel: FolderViewModel) {
        self.sessionStore = sessionStore
        self.folderViewModel = folderViewModel
    }

    nonisolated func resolve(agent: AgentID) async throws -> ResolvedAgent {
        let folder: FolderRegistration? = await MainActor.run {
            self.folderViewModel.folders.first { folder in
                ControlTowerEnvironment.syntheticAgentID(for: folder.id) == agent
            }
        }
        guard let folder else {
            throw AgentResolverError.unknownAgent(id: agent)
        }
        // 캐시 miss → 자동 ensureSession (relay 가 미열린 폴더로 dispatch 시 보장)
        let viewModel = await sessionStore.ensureSession(for: folder)
        guard let viewModel else {
            throw AgentResolverError.unknownAgent(id: agent)
        }
        return ResolvedAgent(adapter: viewModel.adapter, session: viewModel.session)
    }
}
