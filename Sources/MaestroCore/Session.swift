import Foundation

/// 에이전트의 **살아있는 CLI 세션** 인스턴스.
///
/// 하나의 에이전트는 하나의 Session 을 갖는다 (적어도 한 시점에). 세션 ID 는 CLI
/// 의 `--resume` 값과 매핑되며, 앱 재시작 후에도 같은 대화를 이어갈 수 있게 한다.
///
/// - Phase 4 `AgentAdapter.createSession/destroySession` 이 Session 수명 관리.
/// - Phase 13 `DispatchService` 가 Session 을 통해 에이전트에 메시지 전달.
/// - Phase 18 UI 가 `status` + `exitCause` 로 배지 표시.
public struct Session: Codable, Hashable, Sendable, Identifiable {
    public let id: SessionID
    public let agentId: AgentID
    public let adapterId: AdapterID
    public let folderPath: URL
    public let createdAt: Date
    public var lastActivityAt: Date
    public var status: SessionStatus
    /// `.terminated` 일 때 종료 원인. `.active`/`.idle` 일 때는 `nil`.
    public var exitCause: SessionExitCause?

    public init(
        id: SessionID,
        agentId: AgentID,
        adapterId: AdapterID,
        folderPath: URL,
        createdAt: Date,
        lastActivityAt: Date,
        status: SessionStatus,
        exitCause: SessionExitCause? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.adapterId = adapterId
        self.folderPath = folderPath
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.status = status
        self.exitCause = exitCause
    }
}

public extension Session {
    /// 상태 전이. 부적합한 전이는 throws.
    ///
    /// `.terminated` 로 전이할 때 `cause` 를 지정. 그 외 전이에서 cause 가 주어지면 무시.
    mutating func transition(
        to newStatus: SessionStatus,
        cause: SessionExitCause? = nil
    ) throws {
        guard status.canTransition(to: newStatus) else {
            throw SessionError.invalidTransition(from: status, to: newStatus)
        }
        status = newStatus
        if newStatus == .terminated {
            exitCause = cause ?? .unspecified
        } else {
            exitCause = nil
        }
    }

    /// 마지막 활동 시각을 갱신. idle sweeper / 표시 UI 용.
    mutating func touch(at time: Date = Date()) {
        lastActivityAt = time
    }
}

/// 세션의 수명 상태. (원인은 `SessionExitCause` 로 분리.)
///
/// 전이 매트릭스:
/// ```
///           →active  →idle  →terminated  (→pending 없음)
/// active      ✓        ✓        ✓
/// idle        ✓        ✓        ✓
/// terminated  ✗        ✗        ✗  (terminal)
/// ```
public enum SessionStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// CLI 프로세스 유효, 실제 작업 진행 중.
    case active
    /// CLI 연결 또는 세션 파일 유효하나 유휴.
    case idle
    /// 종료됨. 재개 불가 (`.active`/`.idle` 로 되돌아갈 수 없음).
    case terminated
}

/// 종료 원인 — 사용자 의도적 종료 vs CLI 크래시 vs 기타 구분.
public enum SessionExitCause: Codable, Hashable, Sendable {
    /// 사용자가 명시적으로 종료 (Phase 18 메뉴 / 단축키).
    case userTerminated
    /// 외부 CLI 프로세스가 비정상 종료 (signal, non-zero exit).
    case crashed(signal: Int32?, exitCode: Int32?)
    /// idle 타임아웃 스위퍼에 의해 종료.
    case idleSwept
    /// 원인 미상 / 초기화 값.
    case unspecified
}

extension SessionStatus {
    func canTransition(to target: SessionStatus) -> Bool {
        switch (self, target) {
        case (.terminated, _):
            return false  // terminal — 종료 후 재개/재종료 불가
        case (_, .terminated):
            return true   // 언제든 종료 가능 (자기 자신 제외는 위에서 차단)
        case (.active, .idle), (.idle, .active):
            return true
        case (.active, .active), (.idle, .idle):
            return true   // no-op 허용
        }
    }
}

public enum SessionError: Error, Equatable {
    case invalidTransition(from: SessionStatus, to: SessionStatus)
}
