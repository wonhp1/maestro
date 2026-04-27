import MaestroCore
import SwiftUI

/// Phase v0.4.3 — 토론 시작 진입점 + start request → engine 변환 로직.
///
/// `ControlTowerView` 의 file_length 한도 (500) 회피용 분리. 의미는 한 묶음.
extension ControlTowerEnvironment {
    /// v0.5.0 — 토론 dispatch + 결론 요약에 공통 사용되는 IsolatedSessionFactory.
    func makeIsolatedSessionFactory(
        folderViewModel: FolderViewModel
    ) -> MaestroIsolatedSessionFactory {
        MaestroIsolatedSessionFactory(
            folderViewModel: folderViewModel,
            adapterRegistry: adapterRegistry
        )
    }

    /// v0.5.0 — DiscussionViewModel 에 주입할 결론 요약기. 호출 시점마다 새 인스턴스.
    func makeConclusionSummarizer(
        folderViewModel: FolderViewModel
    ) -> DiscussionConclusionSummarizer {
        MaestroDiscussionConclusionSummarizer(
            factory: makeIsolatedSessionFactory(folderViewModel: folderViewModel),
            summarizer: AgentID(rawValue: "control")
        )
    }

    /// v0.5.0 — DiscussionViewModel 에 주입할 결론 공유기. ChatSessionStore 가
    /// 자식 메인 세션에 typing.
    func makeConclusionSharer(
        folderViewModel: FolderViewModel
    ) -> DiscussionConclusionSharing {
        MaestroConclusionSharer(
            chatSessionStore: chatSessionStore,
            folderViewModel: folderViewModel
        )
    }

    /// v0.5.4 — 디스크에서 로드한 record 를 보기용 viewModel 로 복원.
    /// 복원된 토론은 "history-only" — 새 dispatch 는 기대 X. 사용자는 envelopes /
    /// 결론 / 메타를 볼 수 있고 evict 로 삭제 가능.
    func restoreDiscussionViewModel(
        from record: DiscussionRecord
    ) async -> DiscussionViewModel {
        let dispatcher = NoopRestoreDispatcher()
        let engine = DiscussionEngine(
            discussion: record.discussion,
            moderator: RoundRobinModerator(),
            dispatcher: dispatcher,
            initialPrompt: record.discussion.title
        )
        let viewModel = DiscussionViewModel(
            discussion: record.discussion, engine: engine
        )
        viewModel.restoreEnvelopes(record.envelopes)
        return viewModel
    }

    /// "+ 새 토론" 시트의 backing viewModel — 현재 폴더 목록을 참가자 옵션으로,
    /// startAction 은 `startDiscussion` 으로 위임.
    public func makeDiscussionStartViewModel() -> DiscussionStartViewModel {
        let folders = folderViewModel?.folders ?? []
        let options: [DiscussionParticipantOption] = folders
            .filter { !ControlAgentProvisioner.isControlFolder($0.id) }
            .map { folder in
                DiscussionParticipantOption(
                    agentId: ControlTowerEnvironment.syntheticAgentID(for: folder.id),
                    displayName: folder.displayName
                )
            }
        return DiscussionStartViewModel(
            availableParticipants: options,
            startAction: { [weak self] request in
                guard let self else { throw DiscussionStartError.invalidInput }
                return try await self.startDiscussion(request: request)
            }
        )
    }

    /// `DiscussionStartRequest` 를 실제 토론 객체 + engine + viewModel 으로 구체화.
    /// 시작 후 store 에 등록, ThreadID 반환.
    /// v0.5.0: `IsolatedTurnDispatcher` 로 자식 메인 세션 격리 (토론 발언이 자식
    /// 일반 채팅 컨텍스트 오염 차단).
    public func startDiscussion(request: DiscussionStartRequest) async throws -> ThreadID {
        guard let folderViewModel else {
            throw DiscussionStartError.invalidInput
        }
        let threadId = ThreadID.new()
        let moderatorAgentId: AgentID? = {
            switch request.moderatorChoice {
            case .roundRobin, .random: return nil
            case .llm(let id): return id
            }
        }()
        let discussion = Discussion(
            id: threadId,
            title: request.topic,
            participants: request.participants,
            moderatorId: moderatorAgentId,
            maxTurns: request.maxTurns,
            state: .pending,
            turns: []
        )
        let moderator: ModeratorStrategy
        switch request.moderatorChoice {
        case .roundRobin: moderator = RoundRobinModerator()
        case .random: moderator = RandomModerator()
        case .llm:
            // LLM moderator 는 다음 릴리스에서 활성화. UI 가 노출 안 하므로 정상 경로엔
            // 도달 X. 도달 시는 명시적 에러 — silent fallback 금지 (M1 review).
            throw DiscussionStartError.invalidInput
        }
        let factory = makeIsolatedSessionFactory(folderViewModel: folderViewModel)
        let dispatcher = IsolatedTurnDispatcher(
            factory: factory,
            from: AgentID(rawValue: "control")
        )
        let engine = DiscussionEngine(
            discussion: discussion,
            moderator: moderator,
            dispatcher: dispatcher,
            initialPrompt: request.topic
        )
        let viewModel = DiscussionViewModel(discussion: discussion, engine: engine)
        await discussionStore.register(viewModel: viewModel)
        try await engine.start()
        return threadId
    }
}

/// v0.5.4 — 복원된 history-only 토론용 no-op dispatcher. 실제 호출 안 됨
/// (engine.start 안 함, advance 트리거 X).
private struct NoopRestoreDispatcher: DiscussionDispatching {
    struct NotResumable: Error {}
    func dispatchTurn(
        discussion: Discussion,
        speaker: AgentID,
        prompt: String
    ) async throws -> MessageEnvelope {
        throw NotResumable()
    }
}
