import Foundation
import MaestroCore

/// production 환경에서 폴더 새 세션 생성 시 어떤 어댑터를 쓸지 결정.
///
/// ## 정책
/// 1. `preferences.preferredAdapterID` 가 detect 통과하면 그것 사용
/// 2. 안 되면 `enabledAdapterIDs` 중 첫 번째 detect 통과 항목
/// 3. 모두 실패 → fallback adapter (보통 MockAdapter — UI 검증 + 첫 사용자 경험 보호)
///
/// ## 동시성
/// actor — preferences 읽기 / detect 호출 / Mock fallback 모두 직렬화.
public actor AdapterSelector {
    private let candidates: [String: any AgentAdapter]
    private let fallback: any AgentAdapter

    public init(
        candidates: [String: any AgentAdapter],
        fallback: any AgentAdapter
    ) {
        self.candidates = candidates
        self.fallback = fallback
    }

    /// preferences 의 우선순위 + detect 결과로 어댑터 선택.
    public func select(
        preferred: String?,
        enabled: Set<String>
    ) async -> any AgentAdapter {
        // 1) preferred 시도
        if let pref = preferred,
           enabled.contains(pref),
           let adapter = candidates[pref] {
            let detection = await adapter.detect()
            if detection.isInstalled { return adapter }
        }
        // 2) enabled 중 detect 통과 첫 항목
        for id in enabled.sorted() {
            guard let adapter = candidates[id] else { continue }
            let detection = await adapter.detect()
            if detection.isInstalled { return adapter }
        }
        // 3) fallback
        return fallback
    }

    /// 모든 candidate 의 detect 병렬 실행 — 온보딩 / 환경설정 가시화에 사용.
    public func detectAll() async -> [String: AdapterDetection] {
        let snapshot = candidates
        return await withTaskGroup(of: (String, AdapterDetection).self) { group in
            for (id, adapter) in snapshot {
                group.addTask { (id, await adapter.detect()) }
            }
            var result: [String: AdapterDetection] = [:]
            for await (id, detection) in group {
                result[id] = detection
            }
            return result
        }
    }

    /// 표시용 — 설치된 어댑터 ID 목록 (이름 정렬).
    public func installedAdapterIDs() async -> [String] {
        let detections = await detectAll()
        return detections
            .filter { $0.value.isInstalled }
            .keys
            .sorted()
    }
}
