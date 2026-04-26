import Foundation
import Observation

/// 폴더 별 `ChatViewModel` 캐시 — Phase 12 의 다중 세션 지원 핵심.
///
/// ## 책임
/// - 폴더 선택 시 해당 폴더의 ChatViewModel 을 lazily 생성 + 메모리 캐시
/// - 캐시된 인스턴스는 폴더 재선택 시 재사용 (대화 이력 유지)
/// - 폴더 삭제 시 해당 ChatViewModel 제거 + 세션 정리
///
/// ## 의존성
/// - `ChatViewModelFactory` 클로저로 어댑터/세션 생성 외부화 → 테스트 stub 가능
/// - `AgentStatusStore` 주입 — chat 활동 시 status 업데이트
///
/// ## 동시성
/// `@MainActor` — SwiftUI 와 같은 isolation. 세션 생성은 async (어댑터 호출 포함).
///
/// ## 메모리
/// 무제한 캐시 — 단일 사용자 / 수십 폴더 상정. 향후 LRU 도입 시 고려 (Phase 19+).
@MainActor
@Observable
public final class ChatSessionStore {
    public typealias ChatViewModelFactory = @MainActor (FolderRegistration) async throws
        -> ChatViewModel

    /// 폴더 → ChatViewModel 캐시. 외부에서 관찰만 (mutation 은 store 가).
    public private(set) var sessions: [FolderID: ChatViewModel] = [:]
    public private(set) var loadingFolderIDs: Set<FolderID> = []
    public private(set) var lastErrors: [FolderID: String] = [:]

    private let factory: ChatViewModelFactory
    private let statusStore: AgentStatusStore
    /// **single-flight**: 동시 ensureSession 호출이 같은 Task 를 await — 실패 시
    /// 모든 caller 가 같은 nil 결과 + lastErrors 를 본다 (must-fix A2/PERF-1).
    @ObservationIgnored
    private var inFlightTasks: [FolderID: Task<ChatViewModel?, Never>] = [:]

    /// I-NEW-2 fix — factory 가 새 ChatViewModel 의 session.id 를 발급한 직후 호출.
    /// 호스트가 이 hook 으로 FolderRegistry 에 sessionId 를 persist 하면 다음 launch
    /// 가 같은 ID 로 `claude --resume` 가능. nil 이면 no-op (테스트 호환).
    public var onSessionCreated: (@MainActor (FolderID, SessionID) async -> Void)?

    public init(
        factory: @escaping ChatViewModelFactory,
        statusStore: AgentStatusStore
    ) {
        self.factory = factory
        self.statusStore = statusStore
    }

    /// 캐시된 인스턴스 반환 또는 nil.
    public func cached(for folderID: FolderID) -> ChatViewModel? {
        sessions[folderID]
    }

    /// 폴더에 대한 ChatViewModel 보장 — 캐시 hit 또는 single-flight 생성.
    /// 동시 호출은 모두 같은 Task 를 await — 결과 일관 보장 (성공/실패 동일하게 전파).
    @discardableResult
    public func ensureSession(for folder: FolderRegistration) async -> ChatViewModel? {
        if let cached = sessions[folder.id] {
            return cached
        }
        if let existing = inFlightTasks[folder.id] {
            return await existing.value
        }
        loadingFolderIDs.insert(folder.id)
        let task = Task { @MainActor [factory, statusStore] in
            do {
                let viewModel = try await factory(folder)
                self.sessions[folder.id] = viewModel
                self.lastErrors[folder.id] = nil
                statusStore.setIdle(folder.id)
                if let hook = self.onSessionCreated {
                    await hook(folder.id, viewModel.session.id)
                }
                return Optional(viewModel)
            } catch {
                self.lastErrors[folder.id] = error.localizedDescription
                statusStore.setError(folder.id, message: error.localizedDescription)
                return Optional<ChatViewModel>.none
            }
        }
        inFlightTasks[folder.id] = task
        let result = await task.value
        inFlightTasks[folder.id] = nil
        loadingFolderIDs.remove(folder.id)
        return result
    }

    /// 캐시에서 제거 + 상태 초기화 (폴더 삭제 시).
    public func evict(folderID: FolderID) {
        sessions.removeValue(forKey: folderID)
        lastErrors.removeValue(forKey: folderID)
        inFlightTasks[folderID]?.cancel()
        inFlightTasks.removeValue(forKey: folderID)
        statusStore.setOffline(folderID)
    }

    /// 모든 세션 evict (앱 종료 / 진단 시).
    public func evictAll() {
        sessions.removeAll()
        lastErrors.removeAll()
        for task in inFlightTasks.values { task.cancel() }
        inFlightTasks.removeAll()
        statusStore.resetAll()
    }
}
