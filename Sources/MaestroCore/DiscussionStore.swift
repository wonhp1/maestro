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

    public init() {}

    /// 새 토론 등록 + viewModel bind. engine 은 호출자가 미리 만들어 주입.
    @discardableResult
    public func register(viewModel: DiscussionViewModel) async -> DiscussionViewModel {
        let id = viewModel.discussion.id
        viewModels[id] = viewModel
        if !order.contains(id) {
            order.append(id)
        }
        await viewModel.bindEvents()
        return viewModel
    }

    public func get(id: ThreadID) -> DiscussionViewModel? {
        viewModels[id]
    }

    /// 사용자가 토론 목록에서 제거. engine 은 terminate 후 정리.
    public func evict(id: ThreadID) async {
        guard let viewModel = viewModels[id] else { return }
        await viewModel.terminate()
        viewModel.unbindEvents()
        viewModels.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    public var orderedViewModels: [DiscussionViewModel] {
        order.compactMap { viewModels[$0] }
    }

    /// 현재 활성 토론들 (state == .active).
    public var activeViewModels: [DiscussionViewModel] {
        orderedViewModels.filter { $0.state == .active }
    }
}
