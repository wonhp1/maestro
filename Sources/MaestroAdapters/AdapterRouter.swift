import Foundation
import MaestroCore

/// 폴더 → 어댑터 라우팅 — `AdapterSelector` 의 single-method extension.
///
/// **회귀 가드 위치**: v0.9.6 critical 회귀 (codex/gemini 폴더가 항상 Claude 로
/// dispatch) 의 직접 단위 테스트가 가능하게 하는 핵심. ChatFactory 클로저 (executable
/// 타깃, 단위 테스트 불가) 는 이 함수 한 줄을 호출하므로 라우팅 로직이 라이브러리
/// 타깃 안에 있게 됨.
extension AdapterSelector {
    /// `enabled` 셋은 `allCandidateIDs()` 로 자동 결정 — 새 어댑터 등록 시 코드 변경 없이 라우팅.
    public func resolve(folder: FolderRegistration) async -> any AgentAdapter {
        await select(
            preferred: folder.adapterId.rawValue,
            enabled: allCandidateIDs()
        )
    }
}
