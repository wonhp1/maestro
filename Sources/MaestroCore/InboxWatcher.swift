import Foundation

/// 한 에이전트의 `inbox/<agent>/` 디렉토리를 감시하고 새로 생긴 envelope 파일 URL 을
/// emit 하는 actor.
///
/// ## 동작
/// 1. **부팅 시 replay**: 이미 디렉토리에 있는 envelope 파일들을 모두 emit (앱
///    재시작 후 미처리 봉투 회수). 처리한 ID 는 dedup 집합에 등록.
/// 2. **실시간 감시**: `DirectoryWatcher` 로 디렉토리 변화 감지 → readdir → 미처리
///    파일만 emit.
/// 3. **주기적 재스캔** (기본 5초): `DirectoryWatcher` 가 놓치는 케이스 (rename
///    coalescing, 파일시스템 마운트 변화) 백업 — at-least-once 보장.
///
/// ## 멱등성
/// 같은 envelope 파일을 여러 번 emit 하지 않도록 in-memory `processedIDs` 사용.
/// 단, **재시작 시 초기화** — router 가 디스크의 deliveryStatus 로 dedupe 해야 함.
///
/// ## 동시성
/// actor 직렬화. 외부에서 `start()` 호출 시 background Task 가 watcher + ticker 을
/// 구동하고 ID 를 yield. `stop()` 으로 정리.
///
/// ## 보안
/// 파일명만 `EnvelopeID.validated` 로 통과시킴 — `..`, hidden file (`.foo`), 숨김
/// 디렉토리 차단. 비정상 파일은 silently skip + `invalidFiles` 카운터 증가.
public actor InboxWatcher {
    public let agentId: AgentID
    public let directory: URL
    public let pollInterval: TimeInterval

    private let fileManager: FileManager
    private var processedIDs: Set<String> = []
    private var continuation: AsyncStream<URL>.Continuation?
    private var driverTask: Task<Void, Never>?
    public private(set) var invalidFileCount: Int = 0

    public init(
        agentId: AgentID,
        directory: URL,
        pollInterval: TimeInterval = 5.0,
        fileManager: FileManager = .default
    ) {
        self.agentId = agentId
        self.directory = directory
        self.pollInterval = pollInterval
        self.fileManager = fileManager
    }

    /// 감시 시작. 새 envelope 파일 URL 을 yield 하는 stream 반환. 한 번만 호출 가능.
    public func start() -> AsyncStream<URL> {
        if driverTask != nil {
            // 이미 실행 중 — empty stream 반환 (호출 실수 방지).
            return AsyncStream { continuation in continuation.finish() }
        }
        try? fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let stream = AsyncStream<URL> { continuation in
            self.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.stop() }
            }
        }
        driverTask = Task { [weak self] in
            await self?.drive()
        }
        return stream
    }

    /// 감시 종료 + stream finish.
    public func stop() {
        driverTask?.cancel()
        driverTask = nil
        continuation?.finish()
        continuation = nil
    }

    /// dedup 집합에서 한 ID 강제 제거 — 테스트/재시도 용. 일반 흐름에서는 호출 X.
    public func forget(envelopeId: EnvelopeID) {
        processedIDs.remove(envelopeId.rawValue)
    }

    private func drive() async {
        // 초기 replay
        await scanAndEmit()

        // DirectoryWatcher + 주기적 ticker 병행
        await withTaskGroup(of: Void.self) { group in
            let dir = self.directory
            let interval = self.pollInterval
            group.addTask { [weak self] in
                for await event in DirectoryWatcher.events(for: dir) {
                    if Task.isCancelled { break }
                    if case .changed = event {
                        await self?.scanAndEmit()
                    } else {
                        await self?.stop()
                        break
                    }
                }
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    let nanos = UInt64(interval * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    if Task.isCancelled { break }
                    await self?.scanAndEmit()
                }
            }
            await group.waitForAll()
        }
    }

    private func scanAndEmit() async {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        // `createdAt` ordering 은 router 측에서 envelope 로드 후 결정.
        // 여기서는 파일명 사전순 정렬 — 재현 가능 + 같은 createdAt 시 deterministic.
        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in sorted {
            guard url.pathExtension == "json" else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            // 파일명이 envelope ID 형식이어야 함 (path traversal 차단).
            guard (try? EnvelopeID.validated(rawValue: stem)) != nil else {
                invalidFileCount += 1
                continue
            }
            if processedIDs.contains(stem) { continue }
            processedIDs.insert(stem)
            continuation?.yield(url)
        }
    }
}
