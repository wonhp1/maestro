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
    @State private var dockBadgeUpdater: DockBadgeUpdater?
    @State private var onboardingViewModel: OnboardingViewModel?
    @State private var showFeedbackSheet: Bool = false

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
            // Dock 뱃지 업데이터는 view 의 lifetime 에 묶음 — 메뉴바 Scene 은 별도 Scene 이라 root view 가 안전.
            if dockBadgeUpdater == nil {
                let updater = DockBadgeUpdater(summary: environment.activitySummary)
                updater.start()
                dockBadgeUpdater = updater
            }
        }
        .onDisappear {
            dockBadgeUpdater?.stop()
            dockBadgeUpdater = nil
        }
        // canDeleteSelectedFolder 동기화
        .onChange(of: environment.folderViewModel?.selectedFolderID) { _, newValue in
            environment.menuActionRouter.canDeleteSelectedFolder = newValue != nil
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
        .sheet(isPresented: $environment.showOnboarding) {
            if let viewModel = onboardingViewModel {
                OnboardingView(viewModel: viewModel) {
                    await environment.folderViewModel?.addFolderViaPicker()
                }
            }
        }
        .onChange(of: environment.preferencesStore?.snapshot.firstRunCompleted) { _, completed in
            if completed == true { environment.showOnboarding = false }
        }
        .task(id: environment.preferencesStore != nil) {
            if let prefs = environment.preferencesStore, onboardingViewModel == nil {
                let vm = OnboardingViewModel(preferences: prefs)
                vm.setDetectedAdapters(environment.detectedAdapterIDs)
                onboardingViewModel = vm
            }
        }
        .onChange(of: environment.detectedAdapterIDs) { _, ids in
            onboardingViewModel?.setDetectedAdapters(ids)
        }
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackSheetView(detectedAdapters: environment.detectedAdapterIDs)
        }
        .onAppear {
            environment.menuActionRouter.onOpenHelp = { @MainActor in
                if let url = URL(string: "https://github.com/wonhp1/maestro/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
            environment.menuActionRouter.onSendFeedback = {
                Task { @MainActor in showFeedbackSheet = true }
            }
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
    public let slashCommandRegistry: SlashCommandRegistry
    public let menuActionRouter: MenuActionRouter
    public let activitySummary: AppActivitySummary
    public let notificationService: NotificationService
    public let apiKeyStorage: APIKeyStorage
    public let adapterSelector: AdapterSelector?
    public internal(set) var detectedAdapterIDs: [String] = []
    /// bootstrap() 후 set — 실제 디스크 경로로 생성. 그 전엔 nil.
    public private(set) var preferencesStore: PreferencesStore?
    public private(set) var folderViewModel: FolderViewModel?
    public private(set) var dispatchService: DispatchService?
    public internal(set) var pendingSlashInsertion: String?
    public private(set) var resolvedPaths: AppSupportPaths?
    /// `MaestroApp` 가 메인 윈도우에 onboarding sheet 띄울지 여부.
    public var showOnboarding: Bool = false

    @ObservationIgnored
    private let pathsProvider: () throws -> AppSupportPaths
    @ObservationIgnored
    private let pickerFactory: @MainActor () -> FolderPicking
    @ObservationIgnored
    private let envelopeStorage: EnvelopeStorage = EnvelopeStorage()
    @ObservationIgnored
    var slashCommandWatcher: SlashCommandWatcher?
    @ObservationIgnored
    var summaryObservationTask: Task<Void, Never>?
    @ObservationIgnored
    var inboxNotificationBridge: InboxNotificationBridge?

    public init(
        pathsProvider: @escaping () throws -> AppSupportPaths,
        pickerFactory: @escaping @MainActor () -> FolderPicking,
        chatViewModelFactory: @escaping @MainActor (FolderRegistration) async throws
            -> ChatViewModel,
        statusStore: AgentStatusStore = AgentStatusStore(),
        inboxStore: InboxStore = InboxStore(),
        orchestrationStatus: OrchestrationStatusModel = OrchestrationStatusModel(),
        notificationService: NotificationService? = nil,
        preferencesStore: PreferencesStore? = nil,
        apiKeyStorage: APIKeyStorage = APIKeyStorage(),
        adapterSelector: AdapterSelector? = nil
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
        self.slashCommandRegistry = SlashCommandRegistry()
        self.menuActionRouter = MenuActionRouter()
        self.activitySummary = AppActivitySummary()
        self.notificationService = notificationService ?? NoopNotificationService()
        self.apiKeyStorage = apiKeyStorage
        self.adapterSelector = adapterSelector
        // PreferencesStore 는 bootstrap() 에서 paths 해결 후 생성.
        // 호출자가 명시적 store 주입 시 (테스트) 그대로 사용.
        self.preferencesStore = preferencesStore
    }

    /// DispatchComposer 가 읽고 가져간 후 nil 로 클리어.
    public func consumePendingSlashInsertion() -> String? {
        defer { pendingSlashInsertion = nil }
        return pendingSlashInsertion
    }

    /// production 기본 환경 — NSOpenPanelFolderPicker + AdapterSelector (Phase 24).
    /// preferred adapter detect 통과 시 그것 사용, 모두 실패 시 MockAdapter fallback (UI 검증).
    public static func makeProduction() -> ControlTowerEnvironment {
        let candidates: [String: any AgentAdapter] = {
            var map: [String: any AgentAdapter] = [:]
            if let claude = try? ClaudeAdapter() {
                map[ClaudeAdapter.id] = claude
            }
            if let aider = try? AiderAdapter() {
                map[AiderAdapter.id] = aider
            }
            return map
        }()
        let mock = MockAdapter()
        let selector = AdapterSelector(candidates: candidates, fallback: mock)
        return ControlTowerEnvironment(
            pathsProvider: { try AppSupportPaths.forApplication() },
            pickerFactory: { NSOpenPanelFolderPicker() },
            chatViewModelFactory: { [selector] folder in
                // 호출 시점에 선택 — preferences/detect 결과 반영
                // 환경 자체는 PreferencesStore 가 bootstrap 후 set 되므로 selector 가 stand-alone 으로 적정값 결정
                let adapter = await selector.select(
                    preferred: "claude",
                    enabled: ["claude", "aider"]
                )
                let session = try await adapter.createSession(folderPath: folder.path)
                return try ChatViewModel(adapter: adapter, session: session)
            },
            adapterSelector: selector
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
            self.resolvedPaths = paths
            // PreferencesStore — 디스크 경로 확정된 후 생성 (테스트가 미리 주입한 경우 보존).
            if preferencesStore == nil {
                let store = PreferencesStore(path: paths.preferencesFile)
                await store.bootstrap()
                self.preferencesStore = store
            }
            self.showOnboarding = !(preferencesStore?.snapshot.firstRunCompleted ?? true)
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
            await wireSlashCommands()
            wireMenuActions(paths: paths, folderViewModel: viewModel)
            startSummaryObservation()
            await requestNotificationAuthorization()
            await detectInstalledAdapters()
            startInboxNotificationBridge()
            installCrashReporter(paths: paths)
            await runDataMigrations(paths: paths)
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
