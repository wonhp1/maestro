import Foundation

/// 봉투 라우팅의 중앙 오케스트레이터.
///
/// ## 책임 (Phase 11)
/// 1. **dispatch(envelope)**: in-process 직접 디스패치 — inbox 파일 거치지 않음.
/// 2. **bind(agent:)**: 특정 에이전트의 inbox 디렉토리를 감시 시작 — 파일 drop 시
///    자동 디스패치.
/// 3. **응답 처리**: adapter.sendMessage 결과 reply 봉투를 outbox/<sender>/ 로 기록 +
///    threads/<id>.jsonl append.
/// 4. **at-least-once + dedupe**: 같은 envelopeId 의 inbox 파일 처리 후 삭제. 디스크
///    `deliveryStatus` 로 재시작 후에도 중복 디스패치 회피.
/// 5. **DLQ**: dispatch 실패 시 inbox 파일을 `failed/<envelopeId>.json` 으로 이동.
///
/// ## 동시성
/// actor 직렬화. 여러 inbox 봉투가 동시 도착해도 dispatch 호출 자체는 큐잉 — 봉투
/// 처리 자체는 nonisolated 으로 분기시켜 병렬 가능 (`processConcurrent`).
///
/// ## 보안 / 신뢰 경계
/// - 봉투 파일명 = envelopeId — `EnvelopeID.validated` 통과만 dispatch.
/// - **`envelope.to` 검증**: watcher 의 agentId 와 일치해야 함. 불일치 시 DLQ.
/// - **`envelope.from` 신뢰**: 현 단계 router 는 from 을 신뢰. 즉, `inbox/<agent>/`
///   에 쓸 수 있는 모든 주체는 임의 `from` 으로 위조 가능. **신뢰 모델**: 단일
///   사용자 로컬 환경 — 같은 uid 의 모든 코드는 신뢰. 다중 사용자 / 외부 입력
///   확장 시 (Phase 12+ Settings 의 "허용 sender" 화이트리스트 또는 서명 봉투)
///   재검토 필요.
/// - `from` 위조에 대한 추가 방어선: AppSupportPaths 디렉토리 0700 perms 가
///   다른 로컬 사용자의 inbox 쓰기를 차단.
public actor EnvelopeRouter {
    private let paths: AppSupportPaths
    private let storage: EnvelopeStorage
    private let logger: ThreadLogger
    private let resolver: AgentResolving
    private var watchers: [AgentID: InboxWatcher] = [:]
    private var watcherTasks: [AgentID: Task<Void, Never>] = [:]
    private var activeDispatches: [String: Task<Void, Never>] = [:]
    public private(set) var deliveredCount: Int = 0
    public private(set) var failedCount: Int = 0

    public init(
        paths: AppSupportPaths,
        storage: EnvelopeStorage,
        logger: ThreadLogger,
        resolver: AgentResolving
    ) {
        self.paths = paths
        self.storage = storage
        self.logger = logger
        self.resolver = resolver
    }

    deinit {
        for task in watcherTasks.values { task.cancel() }
        for task in activeDispatches.values { task.cancel() }
    }

    /// 봉투를 즉시 디스패치 (inbox 파일 거치지 않음). 응답 봉투 반환.
    /// 호출자는 inbox 에 먼저 write 한 뒤 이 메서드를 호출 — at-least-once 보장.
    @discardableResult
    public func dispatch(_ envelope: MessageEnvelope) async throws -> MessageEnvelope {
        // 1. thread 에 입력 봉투 기록 (deliveryStatus 는 .pending 상태로)
        try await logger.log(envelope)

        // 2. resolve target adapter + session
        let resolved: ResolvedAgent
        do {
            resolved = try await resolver.resolve(agent: envelope.to)
        } catch {
            failedCount += 1
            let failedEnv = envelope.with(deliveryStatus: .failed)
            try? await logger.log(failedEnv)
            throw EnvelopeRouterError.resolveFailure(
                envelopeId: envelope.id, underlying: "\(error)"
            )
        }

        // 3. dispatch via adapter — sendMessage 가 응답 봉투 반환
        let reply: MessageEnvelope
        do {
            reply = try await resolved.adapter.sendMessage(envelope, in: resolved.session)
        } catch {
            failedCount += 1
            let failedEnv = envelope.with(deliveryStatus: .failed)
            try? await logger.log(failedEnv)
            throw EnvelopeRouterError.dispatchFailure(
                envelopeId: envelope.id, underlying: "\(error)"
            )
        }

        // 4. 응답 봉투 정규화 — inReplyTo / threadId / from / to 강제
        let normalizedReply = normalize(reply: reply, to: envelope)

        // 5. outbox 에 응답 기록 + thread 누적
        let outboxPath = paths.outboxFile(agent: envelope.from, envelope: normalizedReply.id)
        try await storage.write(normalizedReply, to: outboxPath)
        try await logger.log(normalizedReply)
        deliveredCount += 1
        return normalizedReply
    }

    /// 한 에이전트의 inbox 디렉토리 감시 시작. 파일 drop 시 자동 디스패치 + 파일 삭제.
    /// 같은 agentId 로 두 번 호출 시 두 번째는 no-op.
    public func bindInbox(for agentId: AgentID) async {
        guard watchers[agentId] == nil else { return }
        let watcher = InboxWatcher(
            agentId: agentId,
            directory: paths.inboxDir(for: agentId)
        )
        watchers[agentId] = watcher

        let stream = await watcher.start()
        let task = Task { [weak self] in
            for await url in stream {
                guard let self else { break }
                await self.processInboxFile(at: url, agent: agentId)
            }
        }
        watcherTasks[agentId] = task
    }

    /// 모든 inbox 감시 종료. **graceful** — 진행 중 dispatch 가 끝날 때까지 await
    /// (개별 작업이 실제로 완료되도록 cancel 하지 않음 → in-flight 결과 손실 방지).
    /// 새 dispatch 는 watcher stop 으로 차단됨.
    public func unbindAll() async {
        for (id, watcher) in watchers {
            await watcher.stop()
            watchers[id] = nil
        }
        for (id, task) in watcherTasks {
            task.cancel()
            _ = await task.value  // watcher stream 종료 후 task 자연 종료 대기
            watcherTasks[id] = nil
        }
        // 진행 중 dispatch 는 cancel 하지 않고 await — 적어도 한 번 보장.
        let pending = activeDispatches.values
        activeDispatches.removeAll()
        for task in pending {
            _ = await task.value
        }
    }

    /// 디스크의 inbox 파일 한 건 처리 — 로드 → dispatch → 삭제 (실패 시 DLQ 이동).
    /// **disk-truth dedupe**: in-memory `activeDispatches` 외에도 호출 시점에
    /// 파일 존재 여부 확인 — 이전 처리가 이미 완료/이동했으면 즉시 return.
    private func processInboxFile(at url: URL, agent: AgentID) async {
        let key = url.path
        if activeDispatches[key] != nil { return }
        if !(await storage.exists(at: url)) { return }
        let task = Task { [weak self] in
            await self?.handleInboxFile(at: url, agent: agent, key: key)
            return ()
        }
        activeDispatches[key] = task
    }

    private func handleInboxFile(at url: URL, agent: AgentID, key: String) async {
        defer { activeDispatches[key] = nil }
        let envelope: MessageEnvelope
        do {
            envelope = try await storage.read(from: url)
        } catch {
            // 디코드 실패 — DLQ 로 이동. 파일명 stem 으로 forensic id 보존.
            let salvageId = recoverEnvelopeID(from: url)
            await moveToDLQ(url: url, envelopeId: salvageId, reason: "decode-failed: \(error)")
            return
        }
        guard envelope.to == agent else {
            await moveToDLQ(
                url: url, envelopeId: envelope.id,
                reason: "envelope.to (\(envelope.to)) != watcher agent (\(agent))"
            )
            return
        }
        do {
            _ = try await dispatch(envelope)
            try await storage.delete(at: url)
        } catch {
            await moveToDLQ(
                url: url, envelopeId: envelope.id,
                reason: "dispatch-failed: \(error)"
            )
        }
    }

    /// 디코드 실패한 inbox 파일에서 forensic envelope ID 회수 시도. 파일명이
    /// `<envelopeId>.json` 형식이고 ID 가 validated 통과하면 그대로 사용.
    /// 실패 시 새 UUID 생성 (마지막 수단).
    private func recoverEnvelopeID(from url: URL) -> EnvelopeID {
        let stem = url.deletingPathExtension().lastPathComponent
        if let validated = try? EnvelopeID.validated(rawValue: stem) {
            return validated
        }
        return .new()
    }

    private func moveToDLQ(url: URL, envelopeId: EnvelopeID, reason: String) async {
        let dest = paths.failedFile(envelope: envelopeId)
        do {
            try await storage.move(from: url, to: dest)
        } catch {
            try? await storage.delete(at: url)
        }
        failedCount += 1
        _ = reason  // 향후 MaestroLogger 통합 시 emit
    }

    /// 어댑터가 반환한 reply 봉투의 메타가 누락/불일치 가능 — 원본 envelope 기준으로
    /// 강제 정규화. body / type / createdAt 은 어댑터 결정 존중.
    private func normalize(
        reply: MessageEnvelope, to original: MessageEnvelope
    ) -> MessageEnvelope {
        var normalized = reply
        if normalized.threadId != original.threadId {
            normalized = normalized.with(threadId: original.threadId)
        }
        // inReplyTo / from / to 는 어댑터가 채우지 않는 게 일반적 → 강제 채움
        if normalized.inReplyTo != original.id || normalized.from != original.to
            || normalized.to != original.from {
            normalized = MessageEnvelope(
                id: normalized.id,
                threadId: original.threadId,
                inReplyTo: original.id,
                from: original.to,
                to: original.from,
                type: normalized.type,
                body: normalized.body,
                createdAt: normalized.createdAt,
                expectReply: normalized.expectReply,
                correlationId: normalized.correlationId,
                deliveryStatus: .delivered,
                schemaVersion: normalized.schemaVersion
            )
        } else {
            normalized = normalized.with(deliveryStatus: .delivered)
        }
        return normalized
    }
}

public enum EnvelopeRouterError: Error, Equatable, Sendable {
    case resolveFailure(envelopeId: EnvelopeID, underlying: String)
    case dispatchFailure(envelopeId: EnvelopeID, underlying: String)
}
