import Foundation

/// 에이전트의 **살아있는 CLI 세션** 인스턴스.
///
/// 하나의 에이전트는 하나의 Session 을 갖는다 (적어도 한 시점에). 세션 ID 는 CLI
/// 의 `--resume` 값과 매핑되며, 앱 재시작 후에도 같은 대화를 이어갈 수 있게 한다.
public struct Session: Codable, Hashable, Sendable, Identifiable {
    public let id: SessionID
    public let agentId: AgentID
    public let adapterId: String
    public let folderPath: URL
    public let createdAt: Date
    public var lastActivityAt: Date
    public var status: SessionStatus

    public init(
        id: SessionID,
        agentId: AgentID,
        adapterId: String,
        folderPath: URL,
        createdAt: Date,
        lastActivityAt: Date,
        status: SessionStatus
    ) {
        self.id = id
        self.agentId = agentId
        self.adapterId = adapterId
        self.folderPath = folderPath
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.status = status
    }
}

public extension Session {
    /// 상태 전이. 부적합한 전이는 throws.
    mutating func transition(to newStatus: SessionStatus) throws {
        guard status.canTransition(to: newStatus) else {
            throw SessionError.invalidTransition(from: status, to: newStatus)
        }
        status = newStatus
    }

    /// 마지막 활동 시각을 갱신. idle sweeper / 표시 UI 용.
    mutating func touch(at time: Date = Date()) {
        lastActivityAt = time
    }
}

/// 세션의 수명 상태.
public enum SessionStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// CLI 프로세스 유효, 실제 작업 진행 중.
    case active
    /// CLI 연결 또는 세션 파일 유효하나 유휴.
    case idle
    /// 종료됨. 재개 불가 (`.active`/`.idle` 로 되돌아갈 수 없음).
    case terminated
}

extension SessionStatus {
    func canTransition(to target: SessionStatus) -> Bool {
        switch (self, target) {
        case (.terminated, _):
            return false  // terminal
        case (_, .terminated):
            return true   // 언제든 종료 가능
        case (.active, .idle), (.idle, .active):
            return true
        case (.active, .active), (.idle, .idle):
            return true   // no-op 허용
        default:
            return false
        }
    }
}

public enum SessionError: Error, Equatable {
    case invalidTransition(from: SessionStatus, to: SessionStatus)
}
