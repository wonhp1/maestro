@testable import MaestroCore
import XCTest

final class CommandRegistryTests: XCTestCase {
    /// 정해진 commands 를 반환하는 fixed provider.
    private struct FixedProvider: CommandProvider {
        let items: [Command]
        func commands() async -> [Command] { items }
    }

    private func makeCommand(id: String, title: String, category: CommandCategory = .system) -> Command {
        Command(id: id, title: title, category: category, handler: {})
    }

    func testEmptyQueryReturnsAllInDefaultOrder() async {
        let registry = CommandRegistry()
        await registry.register(FixedProvider(items: [
            makeCommand(id: "z", title: "zebra", category: .system),
            makeCommand(id: "a", title: "apple", category: .folder),
        ]), id: "p1")

        let results = await registry.search(query: "")
        XCTAssertEqual(results.map(\.id), ["a", "z"], "folder priority < system, alphabetical 안에서")
    }

    func testQueryFiltersAndSortsByScore() async {
        let registry = CommandRegistry()
        await registry.register(FixedProvider(items: [
            makeCommand(id: "1", title: "open folder"),
            makeCommand(id: "2", title: "settings"),
            makeCommand(id: "3", title: "open recent"),
        ]), id: "p1")

        let results = await registry.search(query: "open")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.map(\.id).contains("1"))
        XCTAssertTrue(results.map(\.id).contains("3"))
        XCTAssertFalse(results.map(\.id).contains("2"))
    }

    func testMultipleProvidersAreMerged() async {
        let registry = CommandRegistry()
        await registry.register(FixedProvider(items: [makeCommand(id: "a", title: "alpha")]), id: "p1")
        await registry.register(FixedProvider(items: [makeCommand(id: "b", title: "beta")]), id: "p2")
        let results = await registry.search(query: "")
        XCTAssertEqual(Set(results.map(\.id)), ["a", "b"])
    }

    func testUnregisterRemovesProvider() async {
        let registry = CommandRegistry()
        await registry.register(FixedProvider(items: [makeCommand(id: "x", title: "x")]), id: "p1")
        await registry.unregister(id: "p1")
        let results = await registry.search(query: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testQueryTooLongIsTruncatedNotRejected() async {
        let registry = CommandRegistry(maxQueryBytes: 10)
        await registry.register(FixedProvider(items: [makeCommand(id: "1", title: "open folder")]), id: "p1")
        // 매우 긴 query — 첫 10 bytes ("open folde") 로 truncate 되어 매칭
        let results = await registry.search(query: String(repeating: "open folder ", count: 50))
        XCTAssertFalse(results.isEmpty, "truncation 후에도 매칭되어야")
    }

    func testMaxResultsCap() async {
        let registry = CommandRegistry(maxResults: 3)
        let many = (0..<20).map { makeCommand(id: "\($0)", title: "item \($0)") }
        await registry.register(FixedProvider(items: many), id: "p1")
        let results = await registry.search(query: "item")
        XCTAssertEqual(results.count, 3)
    }
}
