import Foundation
import MaestroCore

/// 폴더 → 어댑터 라우팅 helper.
///
/// 책임 분리:
/// - **이 함수**: folder.adapterId 를 selector 에 정확히 전달하는 pure 로직.
///   라이브러리 타깃에 있어 단위 테스트 가능.
/// - **ChatFactory 클로저** (executable 타깃): 이 함수의 결과 + ClaudeAdapter
///   특수 경로 처리 + ChatViewModel 생성.
///
/// v0.10.0 분리 — v0.9.6 critical 회귀 (codex/gemini 폴더가 Claude 로 잘못
/// 라우팅) 의 회귀 가드를 단위 테스트로 가능하게 하기 위한 minimal extraction.
public enum AdapterRouter {
    /// 폴더의 어댑터 ID 와 selector 를 받아 dispatch 할 어댑터를 반환.
    ///
    /// `enabled` 셋은 selector 의 **모든 등록된 candidate** 로 자동 결정.
    /// 새 어댑터가 selector 에 등록되면 별도 코드 변경 없이 라우팅됨.
    public static func resolve(
        folder: FolderRegistration,
        selector: AdapterSelector
    ) async -> any AgentAdapter {
        await selector.select(
            preferred: folder.adapterId.rawValue,
            enabled: selector.allCandidateIDs()
        )
    }
}
