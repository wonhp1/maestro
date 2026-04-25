import Foundation
import Observation

/// 폴더(=에이전트) 별 `AgentStatus` 를 추적하는 `@MainActor @Observable` 저장소.
///
/// ## 책임
/// - 폴더-단위 상태 보관 + SwiftUI 자동 반응
/// - dispatch lifecycle 이벤트 (.starting / .completed / .failed) 를 status 변환
///
/// ## 향후 (Phase 13)
/// `DispatchService` 가 이 store 를 주입받아 디스패치 진행 상황을 push.
/// 현재는 ChatViewModel 의 streaming 상태를 직접 업데이트 하는 방식 fallback.
@MainActor
@Observable
public final class AgentStatusStore {
    public private(set) var statuses: [FolderID: AgentStatus] = [:]

    public init() {}

    public func status(for folderID: FolderID) -> AgentStatus {
        statuses[folderID] ?? .offline
    }

    public func setOffline(_ folderID: FolderID) {
        statuses[folderID] = .offline
    }

    public func setIdle(_ folderID: FolderID, lastActivityAt: Date? = nil) {
        statuses[folderID] = .idle(lastActivityAt: lastActivityAt ?? Date())
    }

    public func setActive(_ folderID: FolderID, operation: String? = nil) {
        // bidi/control 제거 — UI tooltip / status bar 가 spoof 방어 (must-fix).
        statuses[folderID] = .active(operation: DisplayTextSanitizer.sanitize(operation))
    }

    public func setError(_ folderID: FolderID, message: String) {
        statuses[folderID] = .error(
            message: DisplayTextSanitizer.sanitize(message),
            occurredAt: Date()
        )
    }

    /// 모든 폴더의 status 를 한 번에 초기화 (테스트/리셋).
    public func resetAll() {
        statuses.removeAll()
    }

    /// 현재 active 인 폴더 목록 — OrchestrationStatusBar 표시용.
    public var activeFolderIDs: [FolderID] {
        statuses.compactMap { id, status in
            if case .active = status { return id }
            return nil
        }
    }

    /// error 상태인 폴더 — InboxPanel 의 경고 뱃지용.
    public var errorFolderIDs: [FolderID] {
        statuses.compactMap { id, status in
            if case .error = status { return id }
            return nil
        }
    }
}
