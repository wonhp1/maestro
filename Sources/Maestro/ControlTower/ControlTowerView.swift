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
                    inboxStore: environment.inboxStore,
                    adapterRegistry: environment.adapterRegistry,
                    discussionStore: environment.discussionStore,
                    discussionStartViewModelFactory: { environment.makeDiscussionStartViewModel() },
                    selectedDiscussionID: $environment.selectedDiscussionID
                )
            } else {
                ProgressView("초기화 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } content: {
            detailContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    OrchestrationStatusBar(
                        model: environment.orchestrationStatus,
                        agentDisplayResolver: { agentID in
                            environment.folderViewModel?.displayName(for: agentID)
                                ?? agentID.rawValue
                        }
                    )
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
                },
                agentDisplayResolver: { agentID in
                    environment.folderViewModel?.displayName(for: agentID)
                        ?? agentID.rawValue
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
        // canDeleteSelectedFolder 동기화 + I-NEW-8 fix (어떤 경로로든 폴더가 바뀌면
        // 기존 discussion 표시 자동 해제 — palette/⌘1-9/사이드바 모두 통일).
        .onChange(of: environment.folderViewModel?.selectedFolderID) { _, newValue in
            environment.menuActionRouter.canDeleteSelectedFolder = newValue != nil
            if newValue != nil { environment.selectedDiscussionID = nil }
        }
        // Phase 27 — folder 변화 시 control agent 가 읽는 snapshot 갱신
        .onChange(of: environment.folderViewModel?.folders.count) { _, _ in
            if let folders = environment.folderViewModel?.folders {
                environment.folderListSnapshot.update(folders)
            }
        }
        // I-05 fix — ⌘K / ⌘1~⌘9 단축키는 모두 MaestroMenuCommands 의 Window 그룹에
        // 등록. 옛 background hidden Button 패턴은 NavigationSplitView focus 때문에
        // 키 입력 안 받았음.
        // .sheet 의 isPresented 는 반드시 Binding<Bool> 이어야 함. v0.4.6 까지는
        // `Bindable(viewModel).isPresented` 라고 썼는데, 이건 Bool 값 (binding X) 이라
        // sheet 가 처음만 표시되고 dismiss / 항목 선택 후 자동 닫힘이 동작하지 않았음
        // (I-04). Manual Binding 으로 정정.
        .sheet(isPresented: Binding(
            get: { environment.commandPaletteViewModel.isPresented },
            set: { environment.commandPaletteViewModel.isPresented = $0 }
        )) {
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
    private var detailContent: some View {
        if let discussionID = environment.selectedDiscussionID,
           let discussionVM = environment.discussionStore.get(id: discussionID) {
            DiscussionDetailView(
                viewModel: discussionVM,
                onInterrupt: nil,
                summarizer: environment.folderViewModel.map { fvm in
                    environment.makeConclusionSummarizer(folderViewModel: fvm)
                },
                sharer: environment.folderViewModel.map { fvm in
                    environment.makeConclusionSharer(folderViewModel: fvm)
                },
                memoStore: environment.agentMemoStore,
                agentDisplayResolver: environment.folderViewModel.map { fvm in
                    fvm.displayName(for:)
                } ?? { $0.rawValue }
            )
        } else {
            folderDetailContent
        }
    }

    @ViewBuilder
    private var folderDetailContent: some View {
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
    /// 등록된 모든 어댑터 — vendor picker 가 detect 호출에 사용 (Phase v0.4.3).
    public let adapterRegistry: AdapterRegistry
    /// Phase v0.4.3 — 토론 store + UI 진입점.
    public let discussionStore: DiscussionStore
    /// Control 메타 에이전트가 매 호출 시 fresh 폴더 목록 읽도록 하는 thread-safe snapshot (Phase 27).
    public let folderListSnapshot: FolderListSnapshot
    /// v0.5.0 — 토론 결론 영구 메모 저장소. ClaudeAdapter 가 매 sendMessage 마다
    /// `activeMemos(for:)` 로 조회 → systemPrompt 에 append.
    public let agentMemoStore: AgentMemoStore
    public internal(set) var detectedAdapterIDs: [String] = []
    /// Phase v0.4.3 — 사용자가 사이드바에서 선택한 토론 (있을 때 detail 전환).
    public var selectedDiscussionID: ThreadID?
    /// bootstrap() 후 set — 실제 디스크 경로로 생성. 그 전엔 nil.
    public private(set) var preferencesStore: PreferencesStore?
    public private(set) var folderViewModel: FolderViewModel?
    public internal(set) var dispatchService: DispatchService?
    public internal(set) var pendingSlashInsertion: String?
    public private(set) var resolvedPaths: AppSupportPaths?
    /// `MaestroApp` 가 메인 윈도우에 onboarding sheet 띄울지 여부.
    public var showOnboarding: Bool = false

    @ObservationIgnored
    private let pathsProvider: () throws -> AppSupportPaths
    @ObservationIgnored
    private let pickerFactory: @MainActor () -> FolderPicking
    @ObservationIgnored
    let envelopeStorage: EnvelopeStorage = EnvelopeStorage()
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
        adapterSelector: AdapterSelector? = nil,
        adapterRegistry: AdapterRegistry = AdapterRegistry(),
        discussionStore: DiscussionStore = DiscussionStore(),
        folderListSnapshot: FolderListSnapshot = FolderListSnapshot(),
        agentMemoStore: AgentMemoStore = AgentMemoStore(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "maestro-memo-fallback", directoryHint: .isDirectory)
        )
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
        self.adapterRegistry = adapterRegistry
        self.discussionStore = discussionStore
        self.folderListSnapshot = folderListSnapshot
        self.agentMemoStore = agentMemoStore
        // PreferencesStore 는 bootstrap() 에서 paths 해결 후 생성.
        // 호출자가 명시적 store 주입 시 (테스트) 그대로 사용.
        self.preferencesStore = preferencesStore
    }

    /// DispatchComposer 가 읽고 가져간 후 nil 로 클리어.
    public func consumePendingSlashInsertion() -> String? {
        defer { pendingSlashInsertion = nil }
        return pendingSlashInsertion
    }

    // 토론 진입점 메서드는 `ControlTowerEnvironment+Discussion.swift` 로 분리 (file_length).

    /// production 기본 환경 — NSOpenPanelFolderPicker + AdapterSelector (Phase 24).
    /// Control 폴더는 동적 system prompt 가 주입된 별도 ClaudeAdapter (Phase 27).
    public static func makeProduction() -> ControlTowerEnvironment {
        // v0.5.0 — paths 를 makeProduction 에서 한 번 미리 해결해 메모 저장소 path
        // 를 정확히 set. 실패 시 (희귀) temp 폴더 fallback.
        let resolvedPaths = (try? AppSupportPaths.forApplication())
        let memoStore = AgentMemoStore(
            directory: resolvedPaths?.discussionMemosDir
                ?? FileManager.default.temporaryDirectory
                    .appending(path: "maestro-memo", directoryHint: .isDirectory)
        )
        let folderSnapshot = FolderListSnapshot()
        let candidates = collectAdapterCandidates(
            memoStore: memoStore, folderSnapshot: folderSnapshot
        )
        let selector = AdapterSelector(candidates: candidates, fallback: MockAdapter())
        let registry = AdapterRegistry()
        warmupAdapterRegistry(registry: registry, adapters: Array(candidates.values))
        let controlClaudeAdapter = makeControlClaudeAdapter(folderSnapshot: folderSnapshot)
        return ControlTowerEnvironment(
            pathsProvider: { try AppSupportPaths.forApplication() },
            pickerFactory: { NSOpenPanelFolderPicker() },
            chatViewModelFactory: makeChatViewModelFactory(
                selector: selector, controlClaudeAdapter: controlClaudeAdapter
            ),
            adapterSelector: selector,
            adapterRegistry: registry,
            discussionStore: DiscussionStore(),
            folderListSnapshot: folderSnapshot,
            agentMemoStore: memoStore
        )
    }

    private static func collectAdapterCandidates(
        memoStore: AgentMemoStore,
        folderSnapshot: FolderListSnapshot
    ) -> [String: any AgentAdapter] {
        var map: [String: any AgentAdapter] = [:]
        // v0.5.0 — 자식 (project) ClaudeAdapter 는 매 sendMessage 시 그 폴더로 공유된
        // 활성 메모를 systemPrompt 에 inject. session.folderPath 로 합성 agentID
        // 역산 (folderSnapshot 사용) → memoStore.activeMemos(for:) 조회.
        let memoProvider: @Sendable (Session) async -> String? = { [memoStore, folderSnapshot] session in
            // folderPath → folderID → 합성 AgentID
            let folders = folderSnapshot.read()
            guard let folder = folders.first(where: {
                $0.path.standardizedFileURL == session.folderPath.standardizedFileURL
            }) else { return nil }
            let agentID = Maestro.syntheticAgentID(for: folder.id)
            let memos = await memoStore.activeMemos(for: agentID)
            guard !memos.isEmpty else { return nil }
            return DiscussionMemoSystemPrompt.build(memos: memos)
        }
        if let claude = try? ClaudeAdapter(sessionScopedPromptProvider: memoProvider) {
            map[ClaudeAdapter.id] = claude
        }
        if let aider = try? AiderAdapter() { map[AiderAdapter.id] = aider }
        return map
    }

    /// 동기 register (race 차단) — actor.register 는 단순 dict 삽입이라 빠름.
    /// 사용자가 첫 launch 직후 "+ 폴더 추가" 를 눌러도 vendor picker 가 빈 상태로
    /// 뜨지 않도록 함.
    private static func warmupAdapterRegistry(
        registry: AdapterRegistry, adapters: [any AgentAdapter]
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [registry] in
            for adapter in adapters { _ = try? await registry.register(adapter) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + .milliseconds(500))
    }

    private static func makeControlClaudeAdapter(
        folderSnapshot: FolderListSnapshot
    ) -> ClaudeAdapter? {
        try? ClaudeAdapter(appendSystemPromptProvider: { [folderSnapshot] in
            let entries = folderSnapshot.read()
                .filter { !ControlAgentProvisioner.isControlFolder($0.id) }
                .map { folder in
                    ControlAgentSystemPrompt.AgentEntry(
                        agentID: Maestro.syntheticAgentID(for: folder.id).rawValue,
                        displayName: folder.displayName,
                        folderPath: folder.path.path
                    )
                }
            return ControlAgentSystemPrompt.build(agents: entries)
        })
    }

    /// Control 폴더 + adapterId == "claude" → 동적 system prompt 주입된 ClaudeAdapter.
    /// 사용자가 control 폴더 어댑터를 다른 vendor 로 변경한 경우 일반 selector 경로로
    /// 폴백 — system prompt 자동 주입은 Claude 전용 (Phase v0.4.6 한계).
    /// I-NEW-2 — folder 에 영속된 sessionId 를 어댑터에 전달해 prior 대화 재개.
    private static func makeChatViewModelFactory(
        selector: AdapterSelector,
        controlClaudeAdapter: ClaudeAdapter?
    ) -> @MainActor (FolderRegistration) async throws -> ChatViewModel {
        return { folder in
            if ControlAgentProvisioner.isControlFolder(folder.id),
               folder.adapterId.rawValue == "claude",
               let ctrl = controlClaudeAdapter {
                let session = try await ctrl.createSession(
                    folderPath: folder.path,
                    preferredSessionId: folder.sessionId
                )
                return try ChatViewModel(adapter: ctrl, session: session)
            }
            let adapter = await selector.select(
                preferred: folder.adapterId.rawValue,
                enabled: ["claude", "aider"]
            )
            let session = try await adapter.createSession(
                folderPath: folder.path,
                preferredSessionId: folder.sessionId
            )
            return try ChatViewModel(adapter: adapter, session: session)
        }
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
            // v0.5.0 — 메모 디스크에서 로드 (있는 경우만). 실패는 silently — 메모는
            // 개별 파일 단위 자체 복원성 + UI 가 새로 만들 수 있어 차단 X.
            try? await agentMemoStore.loadAll()
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
            // Phase 27 — Control 메타 에이전트 자동 프로비저닝 (이미 있으면 skip)
            _ = try? await ControlAgentProvisioner.provision(
                registry: registry, appSupportRoot: paths.root
            )
            await viewModel.bootstrap()  // 새로 추가된 control 폴더 reload
            // folderListSnapshot 갱신 (control adapter 의 system prompt 가 읽음)
            self.folderListSnapshot.update(viewModel.folders)
            // I-NEW-2 — 새 ChatViewModel 의 sessionId 를 folder 에 persist.
            chatSessionStore.onSessionCreated = { [weak registry] folderID, sessionID in
                guard let registry else { return }
                try? await registry.setSessionId(id: folderID, sessionId: sessionID)
            }
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

    // wireDispatchService 는 ControlTowerEnvironment+Dispatch.swift 로 이전 (file_length).
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
final class ChatSessionAgentResolver: AgentResolving {
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
