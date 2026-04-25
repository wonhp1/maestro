import Foundation

/// `DispatchObserving` 구현 — Phase 12 store 들에 lifecycle 이벤트를 push.
///
/// `OrchestrationStatusModel` / `AgentStatusStore` / `InboxStore` 모두 `@MainActor`
/// 이므로 hop 을 actor 가 책임진다. 폴더 ↔ 에이전트 매핑은 `agentToFolder` 클로저로
/// 외부 주입 — 향후 Phase 14+ 에 합성 AgentID 도입 시 같은 인터페이스로 교체.
public actor ControlTowerDispatchObserver: DispatchObserving {
    private let orchestrationStatus: OrchestrationStatusModel
    private let agentStatus: AgentStatusStore
    private let inbox: InboxStore
    private let agentToFolder: @Sendable (AgentID) async -> FolderID?
    /// Phase v0.4.6 — dispatch 완료 시 호출. ControlTowerEnvironment 가 양쪽 폴더의
    /// ChatViewModel 에 incoming 메시지 / 자식 응답을 주입하여 채팅에 표시.
    private let onDispatchSettled: @Sendable (MessageEnvelope, MessageEnvelope) async -> Void
    /// Phase v0.4.6 — 자식 RELAY 응답 한 건 도착 → parent 의 ChatViewModel 에 follow-up 표시.
    private let onRelayResult: @Sendable (
        _ parentEnvelope: MessageEnvelope,
        _ parentReply: MessageEnvelope,
        _ relayRequest: MessageEnvelope,
        _ relayReply: MessageEnvelope
    ) async -> Void

    public init(
        orchestrationStatus: OrchestrationStatusModel,
        agentStatus: AgentStatusStore,
        inbox: InboxStore,
        agentToFolder: @escaping @Sendable (AgentID) async -> FolderID?,
        onDispatchSettled: @escaping @Sendable (MessageEnvelope, MessageEnvelope) async -> Void
            = { _, _ in },
        onRelayResult: @escaping @Sendable (
            MessageEnvelope, MessageEnvelope, MessageEnvelope, MessageEnvelope
        ) async -> Void = { _, _, _, _ in }
    ) {
        self.orchestrationStatus = orchestrationStatus
        self.agentStatus = agentStatus
        self.inbox = inbox
        self.agentToFolder = agentToFolder
        self.onDispatchSettled = onDispatchSettled
        self.onRelayResult = onRelayResult
    }

    public func relayResultArrived(
        parentEnvelope: MessageEnvelope,
        parentReply: MessageEnvelope,
        relayRequest: MessageEnvelope,
        relayReply: MessageEnvelope
    ) async {
        await onRelayResult(parentEnvelope, parentReply, relayRequest, relayReply)
    }

    public func dispatchStarted(envelope: MessageEnvelope) async {
        let folderID = await agentToFolder(envelope.to)
        let envelopeId = envelope.id
        let from = envelope.from
        let to = envelope.to
        await MainActor.run {
            orchestrationStatus.recordStart(envelopeId: envelopeId, from: from, to: to)
            if let folderID {
                agentStatus.setActive(folderID, operation: "dispatch 처리 중")
            }
        }
    }

    public func dispatchCompleted(envelope: MessageEnvelope, reply: MessageEnvelope) async {
        let folderID = await agentToFolder(envelope.to)
        let envelopeId = envelope.id
        await MainActor.run {
            orchestrationStatus.recordCompletion(envelopeId: envelopeId)
            if let folderID {
                agentStatus.setIdle(folderID)
            }
        }
        await onDispatchSettled(envelope, reply)
    }

    public func dispatchFailed(envelope: MessageEnvelope, error: Error) async {
        let folderID = await agentToFolder(envelope.to)
        let envelopeId = envelope.id
        let message = error.localizedDescription
        await MainActor.run {
            orchestrationStatus.recordFailure(envelopeId: envelopeId, message: message)
            if let folderID {
                agentStatus.setError(folderID, message: message)
            }
        }
    }

    public func dispatchTimedOut(envelope: MessageEnvelope) async {
        let folderID = await agentToFolder(envelope.to)
        let envelopeId = envelope.id
        await MainActor.run {
            orchestrationStatus.recordFailure(
                envelopeId: envelopeId,
                message: "타임아웃 (5분 초과)"
            )
            if let folderID {
                agentStatus.setError(folderID, message: "타임아웃")
            }
        }
    }

    public func replyReceived(reply: MessageEnvelope, sourceFolderHint: FolderID?) async {
        // 응답은 **수신자** (reply.to) 폴더의 보고함에 기록 — 사용자가 control 폴더에서
        // 자식 응답을 종합 확인할 수 있게. 직전 버전은 from 으로 라우팅해 보낸 사람
        // 폴더에만 보였던 버그 (v0.4.5 fix).
        let folderID: FolderID?
        if let hint = sourceFolderHint {
            folderID = hint
        } else {
            if let viaTo = await agentToFolder(reply.to) {
                folderID = viaTo
            } else {
                folderID = await agentToFolder(reply.from)
            }
        }
        guard let id = folderID else { return }
        await MainActor.run {
            inbox.record(envelope: reply, folderID: id)
        }
    }

    public func relaySkipped(from: AgentID, to: AgentID, reason: String) async {
        // Phase 12 단계에서는 별도 surface 없음 — Phase 14+ 진단 패널 후보.
    }
}
