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
    /// **NEW v0.4.8**:
    /// - 자식 응답을 control chat 에 follow-up bubble 로 append (이전엔 dispatch 결과
    ///   를 `_` 로 버려서 control 화면엔 안 떴음 — bug 1).
    /// - withTaskGroup 으로 모든 자식에게 동시 dispatch (이전엔 for-loop await 라 1명
    ///   응답 끝날 때까지 다음 자식 대기 — bug 2).
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
        chatVM.onAssistantResponseComplete = { [weak service, weak chatVM, weak folderViewModel] body in
            guard let service, let chatVM, let folderViewModel else { return }
            let parsed = parser.parse(body)
            guard !parsed.relays.isEmpty else { return }
            // 모든 자식에게 **동시 dispatch** + 응답을 **발행 순서대로** chat 에 append.
            // (TaskGroup 의 yield 순서는 completion 순서라, 응답 시간이 섞이면 사용자가
            // 발행 순서를 잃음. 결과를 dict 에 모은 뒤 relays 순회로 재정렬.)
            var collected: [AgentID: MessageEnvelope] = [:]
            await withTaskGroup(of: (AgentID, MessageEnvelope?).self) { group in
                for relay in parsed.relays {
                    group.addTask { [service] in
                        let reply = (try? await service.dispatch(
                            from: controlAgent,
                            to: relay.target,
                            body: relay.body,
                            expectReply: true
                        )).flatMap { $0 }
                        return (relay.target, reply)
                    }
                }
                for await (target, reply) in group {
                    if let reply { collected[target] = reply }
                }
            }
            // 발행 순서대로 follow-up bubble append (chatVM 은 @MainActor — 클로저
            // 자체가 ChatViewModel 의 onAssistantResponseComplete 시그니처상 MainActor).
            guard let chatVMStrong = chatVM as ChatViewModel? else { return }
            for relay in parsed.relays {
                guard let reply = collected[relay.target] else { continue }
                let label = folderViewModel.folders.first { f in
                    Maestro.syntheticAgentID(for: f.id) == relay.target
                }?.displayName ?? relay.target.rawValue
                chatVMStrong.appendRelayResult(from: label, body: reply.body)
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
                // HIGH fix (v0.4.8) — control 메타 에이전트는 합성 ID 가 아닌 literal
                // "control" 로 dispatch 됨 (wireControlMainChatRelay 의 controlAgent).
                // reply.to == "control" 이 어떤 폴더의 syntheticAgentID 와도 매치
                // 안 돼 replyReceived() 의 fallback 이 reply.from 으로 가서 자식
                // 폴더 inbox 에 잘못 기록됐던 사용자 보고 1번 ("보고함 안 옴") 의 root cause.
                if agentID.rawValue == "control" {
                    return folderViewModel.folders.first(where: { folder in
                        ControlAgentProvisioner.isControlFolder(folder.id)
                    })?.id
                }
                return folderViewModel.folders.first { folder in
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
