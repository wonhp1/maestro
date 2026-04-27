import AppKit
import MaestroAdapters
import MaestroCore
import SwiftUI

/// `ControlTowerEnvironment` bootstrap helper extension — file_length lint 회피용 분리.
extension ControlTowerEnvironment {
    /// Phase 25 — NSException + signal handlers 등록. 글로벌 state 라 첫 호출만 의미.
    /// I-NEW-3: crashes 디렉토리는 `AppSupportPaths.crashesDir` 가 단일 source.
    func installCrashReporter(paths: AppSupportPaths) {
        let reporter = CrashReporter(directory: paths.crashesDir)
        reporter.install()
        // Phase v0.4.3 — 직전 실행에서 캡처된 크래시가 있으면 alert.
        showPendingCrashAlertIfNeeded(reporter: reporter)
    }

    /// 직전 실행 시 capture 된 unread crash report 가 있으면 사용자에게 알림 + 진단 번들
    /// export 옵션 제공.
    private func showPendingCrashAlertIfNeeded(reporter: CrashReporter) {
        let reports: [CrashReport]
        do {
            reports = try reporter.loadPendingReports()
        } catch {
            return  // load 실패는 fatal 아님
        }
        guard !reports.isEmpty else { return }
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "이전 실행에서 \(reports.count) 건의 크래시가 감지됐어요"
            alert.informativeText = "진단 번들로 보내주시면 문제 파악에 큰 도움이 됩니다."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "진단 번들 만들기")
            alert.addButton(withTitle: "나중에")
            let response = alert.runModal()
            // I-NEW-1 fix: "나중에" 버튼은 reports 보존. dismissAll() 은 사용자가 진단
            // 번들을 실제로 export 한 경우에만 호출 — 그래야 다음 launch 에 다시 alert.
            if response == .alertFirstButtonReturn,
               let paths = self.resolvedPaths {
                await DiagnosticsExporter.exportInteractive(paths: paths)
                try? reporter.dismissAll()
            }
        }
    }

    /// Phase 25 — DataMigrator coordinator 부팅 시 실행. 현재 v0 baseline 이라 no-op.
    func runDataMigrations(paths: AppSupportPaths) async {
        let versionFile = paths.root.appending(
            path: "schema-version.json", directoryHint: .notDirectory
        )
        let coordinator = DataMigrationCoordinator(versionFile: versionFile)
        _ = try? await coordinator.migrateIfNeeded()
    }

    /// Phase 24 — 설치된 CLI 어댑터 감지 (병렬). 결과를 onboarding/preferences UI 가 읽음.
    func detectInstalledAdapters() async {
        guard let selector = adapterSelector else { return }
        let installed = await selector.installedAdapterIDs()
        self.detectedAdapterIDs = installed
    }

    /// Phase 24 — Inbox 도착 시 시스템 알림. notificationsEnabled preferences 와 동기.
    func startInboxNotificationBridge() {
        guard inboxNotificationBridge == nil else { return }
        let enabled = preferencesStore?.snapshot.notificationsEnabled ?? true
        let bridge = InboxNotificationBridge(
            inboxStore: inboxStore,
            notificationService: notificationService,
            notificationsEnabled: enabled
        )
        bridge.start()
        self.inboxNotificationBridge = bridge
    }

    /// 메뉴 / 메뉴바가 호출할 액션을 등록.
    func wireMenuActions(paths: AppSupportPaths, folderViewModel: FolderViewModel) {
        menuActionRouter.onAddFolder = { [weak self] in
            await self?.folderViewModel?.addFolderViaPicker()
        }
        menuActionRouter.onDeleteSelectedFolder = { [weak self] in
            await self?.deleteSelectedFolderImpl()
        }
        menuActionRouter.onOpenCommandPalette = { [weak self] in
            await self?.commandPaletteViewModel.present()
        }
        let dataRoot = paths.root
        menuActionRouter.onRevealDataFolder = {
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([dataRoot])
            }
        }
        menuActionRouter.onOpenPreferences = {
            await MainActor.run {
                _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        // I-05 fix — ⌘1~⌘9 폴더 인덱스 전환을 menu Commands 에서 호출하도록 wiring.
        // (옛 ControlTowerView 의 .background hidden Button 은 NavigationSplitView
        // focus 때문에 키 입력 안 받음. menu 등록은 글로벌 활성.)
        menuActionRouter.onSelectFolderByIndex = { [weak self] index in
            await MainActor.run {
                guard let env = self, let viewModel = env.folderViewModel else { return }
                let zeroBased = index - 1
                guard zeroBased >= 0, zeroBased < viewModel.folders.count else { return }
                let folder = viewModel.folders[zeroBased]
                // I-NEW-8 — discussion 활성 시 ⌘1~⌘9 가 무시되지 않도록 clear.
                env.selectedDiscussionID = nil
                Task { await viewModel.select(id: folder.id) }
            }
        }
    }

    func deleteSelectedFolderImpl() async {
        guard let viewModel = folderViewModel,
              let target = viewModel.selectedFolderID else { return }
        await viewModel.deleteFolder(id: target)
    }

    /// orchestrationStatus / inboxStore / folderViewModel 변화를 폴링해 summary 갱신.
    /// withObservationTracking single-fire 우회 — 1s tick.
    func startSummaryObservation() {
        guard summaryObservationTask == nil else { return }
        summaryObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSummaryImpl()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func refreshSummaryImpl() {
        let running = orchestrationStatus.entries.filter { $0.state == .running }.count
        activitySummary.runningDispatchCount = running
        activitySummary.unreadInboxCount = inboxStore.totalUnread
        activitySummary.folderCount = folderViewModel?.folders.count ?? 0
        if let latest = inboxStore.items.first {
            activitySummary.lastInboxArrival = latest.receivedAt
        }
    }

    func requestNotificationAuthorization() async {
        _ = await notificationService.requestAuthorization()
    }

    /// 슬래시 명령 자동 탐색 wiring — builtin (claude -p /help) + `~/.claude/commands` +
    /// `~/.claude/skills`.
    func wireSlashCommands() async {
        let commandsDir = FileSlashCommandSource.defaultUserCommandsURL()
        let skillsDir = SkillSource.defaultUserSkillsURL()
        await slashCommandRegistry.register(
            FileSlashCommandSource(directory: commandsDir, kind: .userFile),
            id: "user-file"
        )
        await slashCommandRegistry.register(
            SkillSource(directory: skillsDir),
            id: "skill"
        )
        // v0.7.0 Phase 3 — AdapterSlashCommandSource 등록.
        // ClaudeAdapter 가 dispatch 응답의 system.init.slash_commands 에서 SDK 환경
        // 동작 가능 builtin 을 capture (background). source 가 매 호출 시 fresh
        // snapshot 받아 popover 에 노출. 첫 dispatch 전엔 빈 배열 → popover 에 안
        // 보임 (cold start trade-off — 첫 메시지 후 builtin 자동 추가).
        if let claude = await adapterRegistry.adapter(for: ClaudeAdapter.id) {
            await slashCommandRegistry.register(
                AdapterSlashCommandSource(adapter: claude),
                id: "adapter-builtin-claude"
            )
        }
        let watcher = SlashCommandWatcher(
            directories: [commandsDir, skillsDir],
            registry: slashCommandRegistry
        )
        await watcher.start()
        self.slashCommandWatcher = watcher
        // v0.7.0 Phase 2 fix — 옛 `<arg-hint>` literal 박는 패턴 제거.
        // SlashSuggestionEngine.applySelection 과 동일 정책: 인수 없으면 `/foo`,
        // 있으면 trailing space 만 (`/foo `). 사용자가 자유롭게 인수 타이핑.
        let provider = SlashCommandPaletteProvider(
            registry: slashCommandRegistry,
            onSelect: { [weak self] discovered in
                guard let self else { return }
                let hasArgs = (discovered.command.arguments?.isEmpty == false)
                let suffix = hasArgs ? " " : ""
                self.pendingSlashInsertion = "/\(discovered.command.name)\(suffix)"
            }
        )
        await commandRegistry.register(provider, id: "slash")
    }
}
