import Foundation

/// 컨트롤 타워 → 에이전트 dispatch 의 고수준 façade.
///
/// ## 책임
/// 1. UI 의 "보내기" 액션을 단일 API 로 노출 (`dispatch(to:body:expectReply:)`).
/// 2. dispatch lifecycle 을 4개 store 에 push:
///    - `OrchestrationStatusModel.recordStart/Completion/Failure`
///    - `AgentStatusStore.setActive/setIdle/setError`
///    - `InboxStore.record(reply)`
///    - (Phase 14+) `ChatSessionStore` 의 ChatViewModel 에 echo append
/// 3. 응답에서 `ReplyParser` 로 `<REPLY_TO>` / `<RELAY_TO>` 추출 → 릴레이 spawn.
/// 4. `expectReply: true` + `timeout` (기본 5분) — 시간 초과 시 throws.
///
/// ## 동시성
/// actor 직렬화. 동일한 envelope 의 중복 dispatch 는 호출자 책임 (envelopeId 유일).
///
/// ## 보안
/// - `body` 는 sanitize 안 함 (user/UI 입력은 ChatViewModel 의 maxBytes cap +
///   adapter 의 envelope.body 검증에 의존).
/// - **릴레이 깊이 cap** (기본 4) — 무한 relay loop 방어.
/// - 릴레이 대상 AgentID 는 `AgentResolving` 통과만 허용 — unknown 은 silently skip.
public actor DispatchService {
    public static let defaultTimeout: TimeInterval = 300  // 5분
    public static let defaultRelayDepth: Int = 4
    /// dispatch body 의 최대 byte — adversarial paste / 거대 본문 방어 (must-fix HIGH-1).
    public static let defaultMaxBodyBytes: Int = 256 * 1024

    private let router: EnvelopeRouter
    private let resolver: AgentResolving
    private let parser: ReplyParser
    private let timeout: TimeInterval
    private let maxRelayDepth: Int
    private let maxBodyBytes: Int
    private let observer: DispatchObserving

    public init(
        router: EnvelopeRouter,
        resolver: AgentResolving,
        observer: DispatchObserving,
        parser: ReplyParser = ReplyParser(),
        timeout: TimeInterval = DispatchService.defaultTimeout,
        maxRelayDepth: Int = DispatchService.defaultRelayDepth,
        maxBodyBytes: Int = DispatchService.defaultMaxBodyBytes
    ) {
        self.router = router
        self.resolver = resolver
        self.parser = parser
        self.observer = observer
        self.timeout = timeout
        self.maxRelayDepth = maxRelayDepth
        self.maxBodyBytes = max(1, maxBodyBytes)
    }

    /// 에이전트로 메시지 dispatch.
    ///
    /// - `from`: 발신 에이전트.
    /// - `to`: 수신 에이전트.
    /// - `body`: **자동 sanitize** — UTF-8 byte cap 적용 + nested REPLY_TO/RELAY_TO 태그
    ///   strip (must-fix HIGH-1, HIGH-3). 사용자/upstream agent 가 위조 dispatch 인젝션
    ///   불가.
    /// - `expectReply: true` 면 응답 봉투 반환. timeout 시 throws.
    @discardableResult
    public func dispatch(
        from: AgentID,
        to: AgentID,
        body: String,
        expectReply: Bool = true,
        thread: ThreadID = .new()
    ) async throws -> MessageEnvelope? {
        let safeBody = sanitizeOutgoingBody(body)
        return try await dispatchInternal(
            envelope: MessageEnvelope.task(
                from: from, to: to, body: safeBody, thread: thread
            ),
            expectReply: expectReply,
            relayDepth: 0
        )
    }

    private func sanitizeOutgoingBody(_ body: String) -> String {
        let stripped = ReplyParser.stripDispatchTags(body)
        if stripped.utf8.count > maxBodyBytes {
            let endIdx = stripped.utf8.index(stripped.utf8.startIndex, offsetBy: maxBodyBytes)
            return String(decoding: stripped.utf8[..<endIdx], as: UTF8.self)
        }
        return stripped
    }

    private func dispatchInternal(
        envelope: MessageEnvelope,
        expectReply: Bool,
        relayDepth: Int
    ) async throws -> MessageEnvelope? {
        // 1. lifecycle: start
        await observer.dispatchStarted(envelope: envelope)

        // 2. timeout-bounded router dispatch
        let reply: MessageEnvelope
        do {
            reply = try await withTimeout(seconds: timeout) {
                try await self.router.dispatch(envelope)
            }
        } catch is DispatchTimeoutError {
            await observer.dispatchTimedOut(envelope: envelope)
            throw DispatchServiceError.timeout(envelopeId: envelope.id)
        } catch {
            await observer.dispatchFailed(envelope: envelope, error: error)
            throw DispatchServiceError.dispatchFailed(
                envelopeId: envelope.id, underlying: "\(error)"
            )
        }

        // 3. lifecycle: completion + reply notification
        await observer.dispatchCompleted(envelope: envelope, reply: reply)
        await observer.replyReceived(reply: reply, sourceFolderHint: nil)

        // 4. RELAY_TO 처리 — depth cap 안에서 재귀 dispatch.
        // v0.4.6: expectReply: true 로 변경 + observer 에 결과 통지 → parent 의
        // ChatView 에 자식 응답이 follow-up 으로 표시됨.
        let parsed = parser.parse(reply.body)
        if !parsed.relays.isEmpty, relayDepth < maxRelayDepth {
            for relay in parsed.relays {
                guard (try? await resolver.resolve(agent: relay.target)) != nil else {
                    await observer.relaySkipped(
                        from: reply.from, to: relay.target,
                        reason: "unknown agent"
                    )
                    continue
                }
                let safeRelayBody = sanitizeOutgoingBody(relay.body)
                let relayEnvelope = MessageEnvelope.task(
                    from: reply.from,
                    to: relay.target,
                    body: safeRelayBody,
                    thread: envelope.threadId
                )
                let relayReply = try? await dispatchInternal(
                    envelope: relayEnvelope,
                    expectReply: true,
                    relayDepth: relayDepth + 1
                )
                if let relayReply {
                    await observer.relayResultArrived(
                        parentEnvelope: envelope,
                        parentReply: reply,
                        relayRequest: relayEnvelope,
                        relayReply: relayReply
                    )
                }
            }
        }

        return expectReply ? reply : nil
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw DispatchTimeoutError()
            }
            guard let first = try await group.next() else {
                throw DispatchTimeoutError()
            }
            group.cancelAll()
            return first
        }
    }
}

private struct DispatchTimeoutError: Error {}

public enum DispatchServiceError: LocalizedError, Equatable, Sendable {
    case timeout(envelopeId: EnvelopeID)
    case dispatchFailed(envelopeId: EnvelopeID, underlying: String)

    /// I-NEW-6 fix — alert UI 가 보여주던 "MaestroCore.DispatchServiceError error 1"
    /// 이라는 cryptic Swift literal 대신 친절한 한국어 메시지.
    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "응답을 기다리는 동안 시간이 초과됐어요."
        case .dispatchFailed(_, let underlying):
            return "메시지 전달이 실패했어요: \(underlying)"
        }
    }
}

/// DispatchService 의 lifecycle 콜백 — Phase 12 store 들에 wiring 하는 인터페이스.
///
/// 분리 이유: DispatchService 는 Core, store 는 `@MainActor` — actor isolation
/// 직접 호출 불가. observer 가 hop 책임.
public protocol DispatchObserving: Sendable {
    func dispatchStarted(envelope: MessageEnvelope) async
    func dispatchCompleted(envelope: MessageEnvelope, reply: MessageEnvelope) async
    func dispatchFailed(envelope: MessageEnvelope, error: Error) async
    func dispatchTimedOut(envelope: MessageEnvelope) async
    func replyReceived(reply: MessageEnvelope, sourceFolderHint: FolderID?) async
    func relaySkipped(from: AgentID, to: AgentID, reason: String) async
    /// Phase v0.4.6 — RELAY_TO 자식 응답 한 건 도착. parent 의 ChatViewModel 에
    /// follow-up 으로 표시할 수 있게 노출. 기본 구현 no-op.
    func relayResultArrived(
        parentEnvelope: MessageEnvelope,
        parentReply: MessageEnvelope,
        relayRequest: MessageEnvelope,
        relayReply: MessageEnvelope
    ) async
}

public extension DispatchObserving {
    func relayResultArrived(
        parentEnvelope: MessageEnvelope,
        parentReply: MessageEnvelope,
        relayRequest: MessageEnvelope,
        relayReply: MessageEnvelope
    ) async {
        // default no-op — 기존 observer 호환
    }
}

/// 테스트용 noop / 카운팅 observer.
public actor RecordingDispatchObserver: DispatchObserving {
    public private(set) var startedEnvelopes: [EnvelopeID] = []
    public private(set) var completedPairs: [(EnvelopeID, EnvelopeID)] = []
    public private(set) var failedEnvelopes: [EnvelopeID] = []
    public private(set) var timedOutEnvelopes: [EnvelopeID] = []
    public private(set) var receivedReplies: [EnvelopeID] = []
    public private(set) var relaySkips: [(AgentID, String)] = []

    public init() {}

    public func dispatchStarted(envelope: MessageEnvelope) async {
        startedEnvelopes.append(envelope.id)
    }
    public func dispatchCompleted(envelope: MessageEnvelope, reply: MessageEnvelope) async {
        completedPairs.append((envelope.id, reply.id))
    }
    public func dispatchFailed(envelope: MessageEnvelope, error: Error) async {
        failedEnvelopes.append(envelope.id)
    }
    public func dispatchTimedOut(envelope: MessageEnvelope) async {
        timedOutEnvelopes.append(envelope.id)
    }
    public func replyReceived(reply: MessageEnvelope, sourceFolderHint: FolderID?) async {
        receivedReplies.append(reply.id)
    }
    public func relaySkipped(from: AgentID, to: AgentID, reason: String) async {
        relaySkips.append((to, reason))
    }
}
