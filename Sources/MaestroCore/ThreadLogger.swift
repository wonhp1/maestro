import Foundation

/// 스레드별 메시지 누적 로거 — `threads/<thread-id>.jsonl` 에 봉투를 append-only.
///
/// ## 책임
/// - 들어오는 봉투를 해당 thread JSONL 파일에 한 줄씩 추가.
/// - per-thread `JSONLAppender<MessageEnvelope>` 를 캐시 (open syscall 절약).
/// - **append-only** — 봉투 수정/삭제 미지원 (envelope 자체가 불변).
///
/// ## 동시성
/// actor 직렬화. 같은 thread 에 동시 append 호출은 큐잉 — 라인 인터리브 없음.
/// 다른 thread 의 append 는 서로 다른 appender 라 병렬 가능 (각 appender 가 actor).
///
/// ## 파일 권한
/// `JSONLAppender` 가 0600 보장. body 가 평문 누적이므로 시크릿 금지 규약 준수.
///
/// ## 메모리 관리 / fd 누수 방어 (Phase 11 perf must-fix)
/// appender 캐시는 **bounded LRU**. 기본 64. macOS 의 default RLIMIT_NOFILE
/// (256) 이하 + 다른 fd 사용처 (FileWatcher, DirectoryWatcher, EnvelopeStorage,
/// JSONLTailer 등) 와의 충돌 회피. 캐시 초과 시 가장 오래 사용 안 한 appender
/// 를 close.
public actor ThreadLogger {
    public static let defaultMaxOpenAppenders: Int = 64

    private let paths: AppSupportPaths
    private var appenders: [ThreadID: JSONLAppender<MessageEnvelope>] = [:]
    private var lruOrder: [ThreadID] = []  // tail = most recently used
    private let maxOpenAppenders: Int
    private let synchronize: Bool

    public init(
        paths: AppSupportPaths,
        synchronize: Bool = true,
        maxOpenAppenders: Int = ThreadLogger.defaultMaxOpenAppenders
    ) {
        self.paths = paths
        self.synchronize = synchronize
        self.maxOpenAppenders = max(1, maxOpenAppenders)
    }

    /// 봉투를 해당 thread 파일에 append. fsync 기본 활성 (at-least-once 시맨틱).
    public func log(_ envelope: MessageEnvelope) async throws {
        let appender = await appender(for: envelope.threadId)
        try await appender.append(envelope)
    }

    /// 여러 봉투를 하나의 thread 에 batch append. 모두 같은 threadId 여야 함.
    public func logAll(_ envelopes: [MessageEnvelope]) async throws {
        guard !envelopes.isEmpty else { return }
        let firstId = envelopes[0].threadId
        for envelope in envelopes where envelope.threadId != firstId {
            throw ThreadLoggerError.mixedThreads(
                expected: firstId, found: envelope.threadId
            )
        }
        let appender = await appender(for: firstId)
        try await appender.appendAll(envelopes)
    }

    /// 활성 appender 핸들 정리 (테스트 / 종료 시).
    public func closeAll() async {
        for appender in appenders.values {
            await appender.close()
        }
        appenders.removeAll()
        lruOrder.removeAll()
    }

    /// 특정 thread 파일의 디스크 경로.
    public func threadFile(for threadId: ThreadID) -> URL {
        paths.threadFile(id: threadId)
    }

    /// 현재 cache 점유 — 테스트/모니터링용.
    public var openAppenderCount: Int { appenders.count }

    private func appender(for threadId: ThreadID) async -> JSONLAppender<MessageEnvelope> {
        if let cached = appenders[threadId] {
            // LRU touch — tail 로 이동
            if let idx = lruOrder.firstIndex(of: threadId) {
                lruOrder.remove(at: idx)
            }
            lruOrder.append(threadId)
            return cached
        }
        // 신규 생성 전에 cap 확인 — 초과 시 LRU evict
        if appenders.count >= maxOpenAppenders, let evictId = lruOrder.first {
            lruOrder.removeFirst()
            if let evictAppender = appenders.removeValue(forKey: evictId) {
                await evictAppender.close()
            }
        }
        let appender = JSONLAppender<MessageEnvelope>(
            path: paths.threadFile(id: threadId),
            synchronize: synchronize
        )
        appenders[threadId] = appender
        lruOrder.append(threadId)
        return appender
    }
}

public enum ThreadLoggerError: Error, Equatable, Sendable {
    case mixedThreads(expected: ThreadID, found: ThreadID)
}
