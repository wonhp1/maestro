import Foundation

/// 런타임에 사용 가능한 `AgentAdapter` 들을 관리하는 **actor**.
///
/// 책임:
/// - 어댑터 등록/해제 (앱 부팅 시 또는 사용자 액션)
/// - id 로 어댑터 조회 (orchestration / dispatch)
/// - 전체 목록 열람 (UI 렌더링)
/// - 일괄 detect (헬스체크 / 진단)
///
/// 동시성: actor 로 직렬화. 다중 등록/조회 동시 호출 안전.
///
/// - Note: 등록 시 같은 id 의 기존 어댑터는 **덮어쓴다** (replace). 명시적 중복
///   금지가 필요한 경우 `register(_:replacingExisting:)` 의 `false` 사용.
public actor AdapterRegistry {
    private var adapters: [String: any AgentAdapter] = [:]

    public init() {}

    /// 어댑터 등록. **기본은 중복 차단** (동일 id 존재 시 throws).
    ///
    /// 의도적 교체는 `replacingExisting: true` 로 명시. 이 변경은 Phase 4 리뷰의
    /// must-fix 결과 — silent replacement 가 footgun 으로 지적됨.
    ///
    /// - Returns: 새로 추가됐으면 `false`, 기존 값을 교체했으면 `true`.
    @discardableResult
    public func register(
        _ adapter: any AgentAdapter,
        replacingExisting: Bool = false
    ) throws -> Bool {
        let id = adapter.id
        let existed = adapters[id] != nil
        if existed, !replacingExisting {
            throw AdapterRegistryError.alreadyRegistered(id: id)
        }
        adapters[id] = adapter
        return existed
    }

    /// id 로 어댑터 제거. 없으면 false 반환 (throws 하지 않음).
    @discardableResult
    public func unregister(id: String) -> Bool {
        adapters.removeValue(forKey: id) != nil
    }

    /// id 로 어댑터 조회. 없으면 nil.
    public func adapter(for id: String) -> (any AgentAdapter)? {
        adapters[id]
    }

    /// 등록된 모든 어댑터 (등록 순서가 아닌 id 사전 순).
    public func allAdapters() -> [any AgentAdapter] {
        adapters.keys.sorted().compactMap { adapters[$0] }
    }

    /// 등록된 어댑터 id 목록 (사전 순).
    public func adapterIds() -> [String] {
        adapters.keys.sorted()
    }

    /// 등록 개수.
    public var count: Int { adapters.count }

    /// 모든 등록 어댑터에 대해 `detect()` 일괄 호출. 결과는 id → detection 매핑.
    /// 각 detect 는 병렬로 수행 (TaskGroup).
    public func detectAll() async -> [String: AdapterDetection] {
        let snapshot = adapters
        return await withTaskGroup(of: (String, AdapterDetection).self) { group in
            for (id, adapter) in snapshot {
                group.addTask {
                    let detection = await adapter.detect()
                    return (id, detection)
                }
            }
            var results: [String: AdapterDetection] = [:]
            for await (id, detection) in group {
                results[id] = detection
            }
            return results
        }
    }
}

public enum AdapterRegistryError: Error, Equatable, Sendable {
    case alreadyRegistered(id: String)
}
