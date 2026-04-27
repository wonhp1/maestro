import Foundation
import Observation

/// v0.5.1 — 메모 관리 UI 의 driving viewModel.
///
/// - 모든 메모를 시간 역순으로 목록.
/// - 활성/비활성 토글 (디스크에 즉시 반영, ClaudeAdapter 가 다음 호출부터 반영).
/// - 본문 편집 (사용자가 결론 정정 시 사용).
/// - 삭제 (영구).
///
/// `@MainActor` — UI 와 같은 isolation. store actor 는 await.
@MainActor
@Observable
public final class AgentMemoViewModel {
    public private(set) var memos: [DiscussionMemo] = []
    public var errorMessage: String?

    private let store: AgentMemoStore

    public init(store: AgentMemoStore) {
        self.store = store
    }

    public func reload() async {
        do {
            try await store.loadAll()
            self.memos = await store.all()
        } catch {
            errorMessage = "메모 목록을 불러올 수 없어요: \(error.localizedDescription)"
        }
    }

    public func toggleActive(memoId: ThreadID, active: Bool) async {
        guard var memo = await store.memo(id: memoId) else { return }
        memo.active = active
        memo.updatedAt = Date()
        do {
            try await store.save(memo)
            self.memos = await store.all()
        } catch {
            errorMessage = "메모 저장 실패: \(error.localizedDescription)"
        }
    }

    public func updateBody(memoId: ThreadID, body: String) async {
        guard var memo = await store.memo(id: memoId) else { return }
        memo.body = body
        memo.updatedAt = Date()
        do {
            try await store.save(memo)
            self.memos = await store.all()
        } catch {
            errorMessage = "메모 저장 실패: \(error.localizedDescription)"
        }
    }

    public func delete(memoId: ThreadID) async {
        do {
            try await store.delete(id: memoId)
            self.memos = await store.all()
        } catch {
            errorMessage = "메모 삭제 실패: \(error.localizedDescription)"
        }
    }

    public func dismissError() { errorMessage = nil }
}
