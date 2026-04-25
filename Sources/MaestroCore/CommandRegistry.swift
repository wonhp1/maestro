import Foundation

/// 모든 `CommandProvider` 들의 commands 를 모으고, 검색 / 정렬 책임지는 actor.
///
/// ## 책임
/// - Provider 등록/해제
/// - `query` 에 대한 fuzzy 검색 — score 정렬
/// - 카테고리 group + 카테고리 정렬 (recent 최우선)
/// - empty query 시 default order (recent + 정렬 우선순위)
///
/// ## 동시성
/// actor 직렬화. provider commands() 호출은 병렬 (TaskGroup) — 느린 provider 가
/// 다른 provider 의 결과를 막지 않음.
///
/// ## 보안
/// query 길이 cap (1 KiB). 너무 긴 입력은 cap.
public actor CommandRegistry {
    public static let defaultMaxQueryBytes: Int = 1024
    public static let defaultMaxResults: Int = 50

    private var providers: [String: CommandProvider] = [:]
    public let maxQueryBytes: Int
    public let maxResults: Int

    public init(
        maxQueryBytes: Int = CommandRegistry.defaultMaxQueryBytes,
        maxResults: Int = CommandRegistry.defaultMaxResults
    ) {
        self.maxQueryBytes = max(1, maxQueryBytes)
        self.maxResults = max(1, maxResults)
    }

    public func register(_ provider: CommandProvider, id: String) {
        providers[id] = provider
    }

    public func unregister(id: String) {
        providers.removeValue(forKey: id)
    }

    /// 모든 provider 의 commands 를 병렬로 모은 후 query 로 필터/정렬.
    public func search(query: String) async -> [Command] {
        let commands = await collectAllCommands()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultOrder(commands)
        }
        let truncated = truncate(trimmed)
        let scored = FuzzyMatcher.filter(items: commands, query: truncated) { $0.title }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.item.category.sortPriority < rhs.item.category.sortPriority
            }
            .prefix(maxResults)
            .map(\.item)
    }

    private func collectAllCommands() async -> [Command] {
        let snapshot = providers
        return await withTaskGroup(of: [Command].self) { group in
            for provider in snapshot.values {
                group.addTask { await provider.commands() }
            }
            var all: [Command] = []
            for await chunk in group {
                all.append(contentsOf: chunk)
            }
            return all
        }
    }

    private func defaultOrder(_ commands: [Command]) -> [Command] {
        let sorted = commands.sorted { lhs, rhs in
            if lhs.category.sortPriority != rhs.category.sortPriority {
                return lhs.category.sortPriority < rhs.category.sortPriority
            }
            return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
        return Array(sorted.prefix(maxResults))
    }

    private func truncate(_ query: String) -> String {
        if query.utf8.count <= maxQueryBytes { return query }
        let endIdx = query.utf8.index(query.utf8.startIndex, offsetBy: maxQueryBytes)
        return String(decoding: query.utf8[..<endIdx], as: UTF8.self)
    }
}
