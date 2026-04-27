import Foundation
import Observation

/// 컨트롤 타워의 토론 목록을 관리하는 `@MainActor @Observable` 저장소.
///
/// ## 책임
/// - 활성/완료 토론 ViewModel 들을 메모리 캐시
/// - 신규 토론 생성 (`startDiscussion`) — engine + viewModel + bind
/// - 종료된 토론 제거 (`evict`) 또는 보관 (`archive`)
///
/// ## 영속화
/// 현 단계 (Phase 15) 는 in-memory 만. Phase 14.12 deferred — 필요하면 Phase 17+
/// 의 settings + JSONL persistence pass 시점에 도입.
@MainActor
@Observable
public final class DiscussionStore {
    public private(set) var viewModels: [ThreadID: DiscussionViewModel] = [:]
    /// 표시 순서 — 생성 순. 종료된 토론도 evict 전까지 남음.
    public private(set) var order: [ThreadID] = []

    /// v0.5.4 — 디스크 영속화. nil 이면 in-memory only (테스트/onboarding).
    @ObservationIgnored
    public var storage: DiscussionStorage?

    /// v0.5.4 — viewModel 의 envelopes/state 변화를 모니터링하는 task.
    /// id → task. evict 시 cancel.
    @ObservationIgnored
    private var saveTasks: [ThreadID: Task<Void, Never>] = [:]

    public init(storage: DiscussionStorage? = nil) {
        self.storage = storage
    }

    /// 새 토론 등록 + viewModel bind. engine 은 호출자가 미리 만들어 주입.
    @discardableResult
    public func register(viewModel: DiscussionViewModel) async -> DiscussionViewModel {
        let id = viewModel.discussion.id
        viewModels[id] = viewModel
        if !order.contains(id) {
            order.append(id)
        }
        await viewModel.bindEvents()
        // v0.5.4 — 즉시 한 번 저장 (메타만이라도 디스크에 표시) + 변화 감지 task 시동.
        await persistNow(viewModel)
        startObserving(viewModel)
        return viewModel
    }

    public func get(id: ThreadID) -> DiscussionViewModel? {
        viewModels[id]
    }

    /// 사용자가 토론 목록에서 제거. engine 은 terminate 후 정리. 디스크에서도 삭제.
    public func evict(id: ThreadID) async {
        guard let viewModel = viewModels[id] else { return }
        await viewModel.terminate()
        viewModel.unbindEvents()
        viewModels.removeValue(forKey: id)
        order.removeAll { $0 == id }
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        if let storage {
            try? await storage.delete(id: id)
        }
    }

    public var orderedViewModels: [DiscussionViewModel] {
        order.compactMap { viewModels[$0] }
    }

    /// 현재 활성 토론들 (state == .active).
    public var activeViewModels: [DiscussionViewModel] {
        orderedViewModels.filter { $0.state == .active }
    }

    /// v0.6.0 — 디스크에서 복원된 history-only 토론 (NoopRestoreDispatcher) 또는
    /// paused/completed 상태 토론을 다시 active 로 살림.
    /// dispatcherFactory 는 production IsolatedTurnDispatcher 를 만들어 주입.
    /// 호출 후 engine.advanceLoop 가 새 dispatcher 로 다음 턴부터 진행.
    public func resume(
        id: ThreadID,
        addingTurns extra: Int,
        dispatcherFactory: @MainActor () -> DiscussionDispatching
    ) async throws {
        guard let viewModel = viewModels[id] else {
            throw DiscussionError.cannotResume(reason: "토론을 찾을 수 없어요.")
        }
        let newDispatcher = dispatcherFactory()
        try await viewModel.engine.resume(
            addingTurns: extra,
            with: newDispatcher
        )
        // /team review LOW — polling save 1초 windows 사이 crash 시 resume state
        // 손실. 즉시 persist 추가.
        await persistNow(viewModel)
    }

    // MARK: - v0.5.4 — Persistence

    /// 부팅 시 디스크에서 모든 토론 record 로드 → viewModel 복원.
    /// engineFactory 가 record 별로 engine 만들어 viewModel 에 주입 (engine 은
    /// 매번 새로 — adapter/factory 결합은 호출자 책임).
    public func loadAllPersisted(
        engineFactory: (DiscussionRecord) async -> DiscussionViewModel?
    ) async {
        guard let storage else { return }
        let records = (try? await storage.loadAll()) ?? []
        for record in records {
            // 이미 메모리에 있으면 skip (e.g., bootstrap 중복 호출).
            if viewModels[record.id] != nil { continue }
            guard let viewModel = await engineFactory(record) else { continue }
            viewModels[record.id] = viewModel
            if !order.contains(record.id) { order.append(record.id) }
            await viewModel.bindEvents()
            startObserving(viewModel)
        }
    }

    private func persistNow(_ viewModel: DiscussionViewModel) async {
        guard let storage else { return }
        let record = DiscussionRecord(
            discussion: viewModel.discussion,
            envelopes: viewModel.envelopes
        )
        try? await storage.save(record)
    }

    /// viewModel 의 envelopes/discussion.state 변화를 polling 으로 디스크 저장.
    /// @Observable 의 직접 onChange 대신 간단한 1초 poll — 토론은 발언 간격이 길어
    /// 비용 무시 가능.
    private func startObserving(_ viewModel: DiscussionViewModel) {
        let id = viewModel.discussion.id
        saveTasks[id]?.cancel()
        saveTasks[id] = Task { [weak self, weak viewModel] in
            var lastEnvCount = -1
            var lastState: DiscussionState?
            var lastConclusion: String??
            while !Task.isCancelled {
                guard let self, let viewModel else { return }
                let envCount = viewModel.envelopes.count
                let state = viewModel.state
                let conclusion = viewModel.discussion.conclusion
                if envCount != lastEnvCount
                    || state != lastState
                    || conclusion != lastConclusion {
                    lastEnvCount = envCount
                    lastState = state
                    lastConclusion = conclusion
                    await self.persistNow(viewModel)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
