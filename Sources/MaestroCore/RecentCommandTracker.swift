import Foundation
import Observation

/// 최근 실행된 커맨드 ID 들을 LRU 로 추적 — 팔레트 상단 "최근" 섹션 driving.
///
/// 메모리 only — Phase 17 persistence pass 에서 disk 저장 검토.
/// 사용자가 같은 명령을 자주 호출하면 자동으로 상단에 노출.
@MainActor
@Observable
public final class RecentCommandTracker {
    public private(set) var recentIDs: [String] = []
    public let capacity: Int

    public init(capacity: Int = 10) {
        self.capacity = max(1, capacity)
    }

    public func record(commandID: String) {
        // 기존 위치 제거 + 최상단 추가 (LRU)
        recentIDs.removeAll { $0 == commandID }
        recentIDs.insert(commandID, at: 0)
        if recentIDs.count > capacity {
            recentIDs.removeLast(recentIDs.count - capacity)
        }
    }

    public func clear() {
        recentIDs.removeAll()
    }

    /// `Command` 목록에서 최근 사용 commands 만 추출 (recent 순서대로).
    /// 중복 ID 가 있어도 fatal error 없이 첫 번째 채택 (must-fix HIGH-1).
    public func recentCommands(in pool: [Command]) -> [Command] {
        let lookup = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return recentIDs.compactMap { lookup[$0] }
    }
}
