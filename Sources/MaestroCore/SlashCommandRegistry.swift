import Foundation

/// 등록된 모든 `SlashCommandSource` 의 결과를 통합 + 캐시 + 변경 broadcast.
///
/// ## 책임
/// - source 등록 / 해제
/// - `snapshot()` — 현재 캐시 (없으면 refresh)
/// - `refresh()` — 모든 source 병렬 호출 + dedupe + sort + cache
/// - `observe()` — refresh 결과를 받는 AsyncStream (UI / 팔레트가 구독)
///
/// ## 동시성
/// actor 직렬화. source.discover() 는 TaskGroup 으로 병렬.
///
/// ## Dedupe
/// `id` (`<source>:<name>`) 기준. 같은 source 안에 같은 이름이 두 번 들어와도 첫 번째만.
/// 다른 source 의 같은 이름은 별개로 둘 다 표출 — UI 가 "내장 vs 사용자 override"
/// 를 가시화 (Phase 17 의도).
public actor SlashCommandRegistry {
    private var sources: [String: SlashCommandSource] = [:]
    private var cache: [DiscoveredSlashCommand]?
    private var continuations: [UUID: AsyncStream<[DiscoveredSlashCommand]>.Continuation] = [:]

    public init() {}

    public func register(_ source: SlashCommandSource, id: String) {
        sources[id] = source
        cache = nil
    }

    public func unregister(id: String) {
        sources.removeValue(forKey: id)
        cache = nil
    }

    /// 등록된 source ID 목록 — 디버깅 / 테스트 용.
    public var registeredSourceIDs: [String] {
        sources.keys.sorted()
    }

    public func snapshot() async -> [DiscoveredSlashCommand] {
        if let cache { return cache }
        return await refresh()
    }

    @discardableResult
    public func refresh() async -> [DiscoveredSlashCommand] {
        let snapshot = sources
        let collected = await withTaskGroup(of: [DiscoveredSlashCommand].self) { group in
            for source in snapshot.values {
                group.addTask { await source.discover() }
            }
            var all: [DiscoveredSlashCommand] = []
            for await chunk in group {
                all.append(contentsOf: chunk)
            }
            return all
        }
        var seen: Set<String> = []
        var unique: [DiscoveredSlashCommand] = []
        for cmd in collected where seen.insert(cmd.id).inserted {
            unique.append(cmd)
        }
        let sorted = unique.sorted { lhs, rhs in
            if lhs.source.sortPriority != rhs.source.sortPriority {
                return lhs.source.sortPriority < rhs.source.sortPriority
            }
            return lhs.command.name.localizedCompare(rhs.command.name) == .orderedAscending
        }
        cache = sorted
        broadcast(sorted)
        return sorted
    }

    /// 변경 stream — 새 구독자는 즉시 현재 cache (있으면) 1회 receive.
    public func observe() -> AsyncStream<[DiscoveredSlashCommand]> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeObserver(id) }
            }
            if let cache { continuation.yield(cache) }
        }
    }

    private func removeObserver(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcast(_ commands: [DiscoveredSlashCommand]) {
        for cont in continuations.values {
            cont.yield(commands)
        }
    }
}
