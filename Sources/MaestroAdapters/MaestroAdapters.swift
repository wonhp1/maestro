// MaestroAdapters — AI CLI 에이전트 어댑터 모듈.
//
// NEXT: Phase 4 에서 `AgentAdapter` 프로토콜로 대체 (PLAN §Phase 4).
// NEXT: Phase 7 에서 Claude Adapter, Phase 9 에서 Aider Adapter 구현.
//
// 현재는 모듈 자체의 존재성만 담당하는 scaffold. MaestroAdaptersTests 타겟도
// Phase 4 에서 재도입 예정.

import MaestroCore

/// Phase 1 scaffold — 모듈 존재성 확인용.
///
/// - Note: Phase 4 에서 `AgentAdapter` 프로토콜과 `AdapterRegistry` 로 대체됨.
public enum MaestroAdapters {
    /// 모듈 식별자. 디버깅/로그용으로만 참조.
    public static let moduleName: String = "MaestroAdapters"
}
