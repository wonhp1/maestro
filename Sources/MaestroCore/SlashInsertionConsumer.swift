import Foundation

/// `pendingSlashInsertion` side-channel (ControlTowerEnvironment) 의 consume 정책.
///
/// Phase 17 review MED-2 에서 `pendingSlashInsertion` 이 set 만 되고 consumer 가
/// 없어 dead 상태였음. v0.7.0 Phase 1 이 `ChatComposer` / `DispatchComposer` 의
/// `onChange(of:)` 에서 호출.
///
/// ## 정책
///
/// - `nil` → consume X (no-op)
/// - whitespace-only → consume X (의미 없는 값)
/// - valid → resolve 로 새 draft 반환, 호출자가 binding 을 nil 로 클리어
///
/// ## 왜 분리?
///
/// SwiftUI `.onChange` 의 logic 을 pure function 으로 분리해 단위 테스트 가능.
/// composer 의 wiring (binding / @State 갱신) 은 manual smoke 로만 검증.
public enum SlashInsertionConsumer {
    /// 의미 있는 pending 값인지 판단. 단위 테스트용.
    public static func shouldConsume(pending: String?) -> Bool {
        guard let pending else { return false }
        return !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// pending 을 새 draft 로 변환. nil/empty 면 nil 반환 → 호출자는 draft 변경 X.
    public static func resolve(pending: String?) -> String? {
        guard shouldConsume(pending: pending) else { return nil }
        return pending
    }
}
