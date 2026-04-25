import AppKit
import MaestroAdapters
import MaestroCore
import SwiftUI

/// `ControlTowerEnvironment` bootstrap helper extension — file_length lint 회피용 분리.
extension ControlTowerEnvironment {
    /// Phase 25 — NSException + signal handlers 등록. 글로벌 state 라 첫 호출만 의미.
    func installCrashReporter(paths: AppSupportPaths) {
        let crashDir = paths.root.appending(path: "crashes", directoryHint: .isDirectory)
        let reporter = CrashReporter(directory: crashDir)
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
            if response == .alertFirstButtonReturn,
               let paths = self.resolvedPaths {
                await DiagnosticsExporter.exportInteractive(paths: paths)
            }
            try? reporter.dismissAll()
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

    /// 슬래시 명령 자동 탐색 wiring — `~/.claude/commands` + `~/.claude/skills`.
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
        let watcher = SlashCommandWatcher(
            directories: [commandsDir, skillsDir],
            registry: slashCommandRegistry
        )
        await watcher.start()
        self.slashCommandWatcher = watcher
        let provider = SlashCommandPaletteProvider(
            registry: slashCommandRegistry,
            onSelect: { [weak self] discovered in
                guard let self else { return }
                let argHint = discovered.command.arguments?.first.map { " <\($0)>" } ?? ""
                self.pendingSlashInsertion = "/\(discovered.command.name)\(argHint)"
            }
        )
        await commandRegistry.register(provider, id: "slash")
    }
}
