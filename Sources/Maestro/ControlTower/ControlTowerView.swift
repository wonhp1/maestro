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
    /// v0.5.1 — 토론 메모 관리 시트.
    @State private var showMemosSheet: Bool = false
    @State private var memoViewModel: AgentMemoViewModel?

    var body: some View {
        NavigationSplitView {
            sidebarContent
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
                        DispatchComposer(
                            folderViewModel: folderViewModel,
                            onSend: { folder, body in
                                await environment.sendDispatch(to: folder, body: body)
                            },
                            slashInsertion: $environment.pendingSlashInsertion
                        )
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
        .modifier(MemoSheetModifier(
            environment: environment,
            showSheet: $showMemosSheet,
            viewModel: $memoViewModel
        ))
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
    private var sidebarContent: some View {
        if let viewModel = environment.folderViewModel {
            SidebarView(
                viewModel: viewModel,
                statusStore: environment.statusStore,
                inboxStore: environment.inboxStore,
                adapterRegistry: environment.adapterRegistry,
                discussionStore: environment.discussionStore,
                discussionStartViewModelFactory: {
                    environment.makeDiscussionStartViewModel()
                },
                onRestartFolderSession: { folderID in
                    // v0.6.0 — 폴더 설정에서 모델/어댑터 변경 후 "지금 적용" →
                    // ChatViewModel 캐시 invalidate. 다음 진입 시 새 modelId 로
                    // createSession.
                    environment.chatSessionStore.evict(folderID: folderID)
                },
                selectedDiscussionID: $environment.selectedDiscussionID
            )
        } else {
            ProgressView("초기화 중…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                } ?? { $0.rawValue },
                // v0.6.0 — folderViewModel 이 준비된 경우에만 factory 주입.
                // nil 이면 DiscussionDetailView 의 "재개" 버튼이 비활성화.
                resumeDispatcherFactory: environment.folderViewModel.map { fvm in
                    { @MainActor in
                        IsolatedTurnDispatcher(
                            factory: environment.makeIsolatedSessionFactory(
                                folderViewModel: fvm
                            ),
                            from: AgentID(rawValue: "control")
                        )
                    }
                }
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
                ChatView(
                    viewModel: chatViewModel,
                    slashInsertion: $environment.pendingSlashInsertion
                )
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
