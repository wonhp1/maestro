import Foundation

/// 지정 디렉토리(`~/.claude/commands`, `~/.claude/skills`)를 감시하다가 변화 시
/// `SlashCommandRegistry.refresh()` 를 호출.
///
/// ## 디바운스
/// 짧은 간격에 여러 변경이 몰리면 최후 변경만 refresh — 진행 중인 디바운스 task 를
/// 취소하고 새로 spawn 하는 형태. 기본 500ms.
///
/// ## 백업 ticker
/// `DirectoryWatcher` 가 놓치는 케이스 (rename coalescing, 마운트 이벤트) 를 위해
/// 주기적 fallback refresh — 기본 30s.
///
/// ## 디렉토리 자체 삭제
/// 감시 dir 이 삭제 / rename 되면 해당 watch loop 는 종료. ticker 가 다음 주기에
/// `createDirectory(...)` 후 refresh 시도 — silently 복구.
///
/// ## 동시성
/// actor — debounce/ticker 모두 actor isolated 함수 호출.
public actor SlashCommandWatcher {
    public let directories: [URL]
    public let registry: SlashCommandRegistry
    public let debounceNanos: UInt64
    public let pollInterval: TimeInterval

    private let fileManager: FileManager
    private var driverTask: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?

    public init(
        directories: [URL],
        registry: SlashCommandRegistry,
        debounceNanos: UInt64 = 500_000_000,
        pollInterval: TimeInterval = 30.0,
        fileManager: FileManager = .default
    ) {
        self.directories = directories
        self.registry = registry
        self.debounceNanos = debounceNanos
        self.pollInterval = max(1.0, pollInterval)
        self.fileManager = fileManager
    }

    public func start() {
        guard driverTask == nil else { return }
        for dir in directories {
            try? fileManager.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        }
        driverTask = Task { [weak self] in
            await self?.drive()
        }
    }

    public func stop() {
        driverTask?.cancel()
        driverTask = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

    /// 호출자 규약: 폐기 전 반드시 `stop()` 호출. `deinit` 에서 actor 격리 mutable
    /// 상태에 접근할 수 없으므로 자동 정리 없음 (Swift 6 strict). InboxWatcher 와
    /// 같은 패턴.
    private func drive() async {
        await registry.refresh()

        await withTaskGroup(of: Void.self) { group in
            for dir in directories {
                group.addTask { [weak self] in
                    await self?.observe(dir: dir)
                }
            }
            group.addTask { [weak self] in
                await self?.tick()
            }
            await group.waitForAll()
        }
    }

    private func observe(dir: URL) async {
        for await event in DirectoryWatcher.events(for: dir) {
            if Task.isCancelled { break }
            switch event {
            case .changed:
                await scheduleRefresh()
            case .deleted, .renamed:
                // ticker 가 디렉토리 재생성 후 다음 refresh 트리거.
                return
            }
        }
    }

    private func tick() async {
        let nanos = UInt64(pollInterval * 1_000_000_000)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { break }
            for dir in directories {
                try? fileManager.createDirectory(
                    at: dir, withIntermediateDirectories: true
                )
            }
            await registry.refresh()
        }
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let nanos = debounceNanos
        let registry = self.registry
        pendingRefresh = Task {
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            await registry.refresh()
        }
    }
}
