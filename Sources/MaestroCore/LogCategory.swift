import Foundation

/// 로그 카테고리 — `MaestroLogger` / `MaestroSignposter` 가 사용. Console.app /
/// Instruments 에서 필터로 활용.
///
/// 카테고리 추가 시 enum 케이스만 늘리면 됨 — 다른 모듈은 영향받지 않음.
public enum LogCategory: String, Hashable, Sendable, CaseIterable {
    /// 어댑터 detect / 세션 lifecycle / 메시지 송수신.
    case adapter
    /// 파일 I/O — FileStore / JSONLAppender / Tailer / Watcher.
    case persistence
    /// Phase 11 EnvelopeRouter, 주소 해석, fan-out — `.dispatch` 와 분리.
    case routing
    /// Phase 13 DispatchService — 재시도, deadline, idempotence.
    case dispatch
    /// Discussion 엔진 (Phase 14), turn 관리 — orchestration umbrella.
    case orchestration
    /// 외부 프로세스 실행 — Process spawn / drain / signal.
    case process
    /// 네트워크 I/O — Sparkle, MCP, HTTP. (Phase 21)
    case network
    /// Keychain, 코드 서명, sandbox 권한 프롬프트.
    case security
    /// SwiftUI 뷰 lifecycle / 사용자 상호작용.
    case ui
    /// 어디에도 분류 안 되는 일반 진단 / 부팅 / 종료.
    case general
}
