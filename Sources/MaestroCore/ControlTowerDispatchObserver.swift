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

    public init(
        orchestrationStatus: OrchestrationStatusModel,
        agentStatus: AgentStatusStore,
        inbox: InboxStore,
        agentToFolder: @escaping @Sendable (AgentID) async -> FolderID?
    ) {
        self.orchestrationStatus = orchestrationStatus
        self.agentStatus = agentStatus
        self.inbox = inbox
        self.agentToFolder = agentToFolder
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
