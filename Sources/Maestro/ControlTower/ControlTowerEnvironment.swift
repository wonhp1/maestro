import MaestroAdapters
import MaestroCore
import SwiftUI

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
    /// v0.7.0 Phase 3 fix — control 폴더 전용 ClaudeAdapter (별도 인스턴스).
    /// 일반 selector 의 adapter 와 다른 actor 라 slash_commands capture 도 별개.
    /// wireSlashCommands 가 둘 다 source 등록.
    @ObservationIgnored
    public let controlClaudeAdapter: ClaudeAdapter?
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
        ),
        controlClaudeAdapter: ClaudeAdapter? = nil
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
        self.controlClaudeAdapter = controlClaudeAdapter
        // PreferencesStore 는 bootstrap() 에서 paths 해결 후 생성.
        // 호출자가 명시적 store 주입 시 (테스트) 그대로 사용.
        self.preferencesStore = preferencesStore
    }

    // v0.7.0 Phase 1: 옛 consumePendingSlashInsertion() 메서드 제거.
    // ChatComposer/DispatchComposer 가 직접 binding mutation 으로 클리어함.

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
            agentMemoStore: memoStore,
            controlClaudeAdapter: controlClaudeAdapter
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

    // makeChatViewModelFactory 는 ControlTowerEnvironment+ChatFactory.swift 로
    // 분리 (file_length).

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
            // v0.5.4 — 토론 디스크 영속화 wiring + 옛 토론 복원 (history-only).
            discussionStore.storage = DiscussionStorage(directory: paths.discussionsDir)
            await discussionStore.loadAllPersisted { [weak self] record in
                await self?.restoreDiscussionViewModel(from: record)
            }
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
