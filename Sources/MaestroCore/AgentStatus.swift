import Foundation

/// 에이전트의 운영 상태 — 사이드바 / 컨트롤 타워의 status 뱃지 driving.
///
/// ## 의미론
/// - `.idle`: 세션 존재, 준비 상태. 마지막 활동 후 일정 시간 경과.
/// - `.active`: 현재 메시지 처리 중 (streaming / tool-use / 사용자 입력 대기).
/// - `.error`: 마지막 dispatch 실패. 에러 메시지 포함.
/// - `.offline`: 세션 미생성 또는 destroy 됨. 첫 진입 폴더의 기본 상태.
///
/// ## UI 매핑
/// - `.active` → 🟢 (정상 운영)
/// - `.idle` → 🟡 (대기)
/// - `.error` → 🔴 (주의 필요)
/// - `.offline` → ⚪ (비활성)
///
/// 향후 Phase 13 의 `DispatchService` 가 dispatch 시작 시 `.active` 로 전이,
/// 완료 시 `.idle`, 실패 시 `.error` 로 전이.
public enum AgentStatus: Sendable, Hashable {
    case offline
    case idle(lastActivityAt: Date?)
    case active(operation: String?)
    case error(message: String, occurredAt: Date)

    /// SF Symbol 컬러 매핑 — UI 가 사용.
    public var symbolColor: AgentStatusColor {
        switch self {
        case .offline: return .gray
        case .idle: return .yellow
        case .active: return .green
        case .error: return .red
        }
    }

    /// 사람이 읽을 수 있는 한 줄 설명.
    public var localizedDescription: String {
        switch self {
        case .offline:
            return "오프라인"
        case .idle(let lastActivity):
            if let last = lastActivity {
                return "대기 (마지막 활동: \(formatted(last)))"
            }
            return "대기"
        case .active(let operation):
            if let op = operation { return "동작 중 — \(op)" }
            return "동작 중"
        case .error(let message, _):
            return "에러: \(message)"
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// AgentStatus 의 UI 색상 — SwiftUI Color 와 분리 (Core 가 SwiftUI 의존 금지).
public enum AgentStatusColor: Sendable, Hashable {
    case gray, yellow, green, red
}
