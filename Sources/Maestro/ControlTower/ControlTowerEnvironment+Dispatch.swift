import MaestroCore
import SwiftUI

/// `ControlTowerEnvironment.wireDispatchService` 분리 — file_length lint 회피.
/// observer 의 onDispatchSettled / onRelayResult 클로저가 ChatViewModel 동기화를
/// 처리하는 큰 블록이라 별도 파일로 옮김.
extension ControlTowerEnvironment {
    /// DispatchService 를 wiring — Phase 13 + Phase v0.4.6 (multi-turn).
    /// 합성 AgentID = "agent-<folder-id>".
    func wireDispatchService(
        paths: AppSupportPaths,
        folderViewModel: FolderViewModel
    ) async {
        let logger = ThreadLogger(paths: paths)
        let resolver = ChatSessionAgentResolver(
            sessionStore: chatSessionStore,
            folderViewModel: folderViewModel
        )
        let router = EnvelopeRouter(
            paths: paths,
            storage: envelopeStorage,
            logger: logger,
            resolver: resolver
        )
        let observer = makeObserver(folderViewModel: folderViewModel)
        let service = DispatchService(
            router: router,
            resolver: resolver,
            observer: observer
        )
        self.dispatchService = service
        await wireControlMainChatRelay(folderViewModel: folderViewModel, service: service)
    }

    /// I-03 fix — control 폴더의 main chat input 으로 들어온 응답에 RELAY_TO 가 있으면
    /// DispatchService 로 spawn. ChatViewModel.send 가 adapter 만 호출하고 끝나므로
    /// 외부에서 onAssistantResponseComplete 훅을 set 해 둠.
    private func wireControlMainChatRelay(
        folderViewModel: FolderViewModel,
        service: DispatchService
    ) async {
        let controlFolder = folderViewModel.folders.first { folder in
            ControlAgentProvisioner.isControlFolder(folder.id)
        }
        guard let controlFolder else { return }
        guard let chatVM = await chatSessionStore.ensureSession(for: controlFolder) else { return }
        let parser = ReplyParser()
        let controlAgent = AgentID(rawValue: "control")
        chatVM.onAssistantResponseComplete = { [weak service] body in
            guard let service else { return }
            let parsed = parser.parse(body)
            for relay in parsed.relays {
                _ = try? await service.dispatch(
                    from: controlAgent,
                    to: relay.target,
                    body: relay.body,
                    expectReply: true
                )
            }
        }
    }

    private func makeObserver(
        folderViewModel: FolderViewModel
    ) -> ControlTowerDispatchObserver {
        ControlTowerDispatchObserver(
            orchestrationStatus: orchestrationStatus,
            agentStatus: statusStore,
            inbox: inboxStore,
            agentToFolder: agentToFolderResolver(folderViewModel: folderViewModel),
            onDispatchSettled: makeDispatchSettledHandler(folderViewModel: folderViewModel),
            onRelayResult: makeRelayResultHandler(folderViewModel: folderViewModel)
        )
    }

    private func agentToFolderResolver(
        folderViewModel: FolderViewModel
    ) -> @Sendable (AgentID) async -> FolderID? {
        return { [weak folderViewModel] agentID in
            guard let folderViewModel else { return nil }
            return await MainActor.run {
                folderViewModel.folders.first { folder in
                    Maestro.syntheticAgentID(for: folder.id) == agentID
                }?.id
            }
        }
    }

    /// 자식 폴더 ChatView 에 dispatch 표시 — recipient (envelope.to) 의 폴더 ChatView
    /// 에 user 메시지 + 자기 응답으로 append.
    private func makeDispatchSettledHandler(
        folderViewModel: FolderViewModel
    ) -> @Sendable (MessageEnvelope, MessageEnvelope) async -> Void {
        return { [weak chatSessionStore = self.chatSessionStore, weak folderViewModel] envelope, reply in
            guard let store = chatSessionStore, let folderViewModel else { return }
            await MainActor.run {
                let folder = folderViewModel.folders.first { folder in
                    Maestro.syntheticAgentID(for: folder.id) == envelope.to
                }
                guard let folder else { return }
                let chatVM = store.cached(for: folder.id)
                let senderLabel = folderViewModel.folders.first { folder in
                    Maestro.syntheticAgentID(for: folder.id) == envelope.from
                }?.displayName ?? envelope.from.rawValue
                chatVM?.injectIncomingDispatch(
                    request: envelope, reply: reply,
                    requestSenderLabel: senderLabel
                )
            }
        }
    }

    /// 부모 chat 에 자식 응답 follow-up. parent 폴더 = 원래 envelope.to (예: control).
    private func makeRelayResultHandler(
        folderViewModel: FolderViewModel
    ) -> @Sendable (MessageEnvelope, MessageEnvelope, MessageEnvelope, MessageEnvelope) async -> Void {
        return { [weak chatSessionStore = self.chatSessionStore, weak folderViewModel] parentEnv, _, relayReq, relayReply in
            guard let store = chatSessionStore, let folderViewModel else { return }
            await MainActor.run {
                let parentFolder = folderViewModel.folders.first { folder in
                    Maestro.syntheticAgentID(for: folder.id) == parentEnv.to
                }
                guard let parentFolder else { return }
                let chatVM = store.cached(for: parentFolder.id)
                let childLabel = folderViewModel.folders.first { folder in
                    Maestro.syntheticAgentID(for: folder.id) == relayReq.to
                }?.displayName ?? relayReq.to.rawValue
                chatVM?.appendRelayResult(from: childLabel, body: relayReply.body)
            }
        }
    }
}
