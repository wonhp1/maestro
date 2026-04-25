// MaestroAdapters — AI CLI 에이전트 어댑터 모듈.
//
// Phase 4: AgentAdapter 프로토콜 (in MaestroCore) + 본 모듈의 구현 유틸:
// - CLIDetector / ExecutableLocating / ProcessExecuting: 어댑터 구현체가 사용하는 공통 도구
// - MockAdapter: 테스트/UI 미리보기 전용 어댑터
//
// 후속 Phase:
// - Phase 7: ClaudeAdapter
// - Phase 9: AiderAdapter

import MaestroCore

/// 모듈 메타데이터. 디버깅/로그 용도.
public enum MaestroAdapters {
    public static let moduleName: String = "MaestroAdapters"
}
