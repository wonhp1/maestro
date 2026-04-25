@testable import MaestroCore
import XCTest

final class SlashCommandRegistryTests: XCTestCase {
    private struct StubSource: SlashCommandSource {
        let items: [DiscoveredSlashCommand]
        func discover() async -> [DiscoveredSlashCommand] { items }
    }

    private func makeCommand(
        name: String,
        source: SlashCommandSourceKind = .userFile
    ) -> DiscoveredSlashCommand {
        DiscoveredSlashCommand(
            command: SlashCommand(name: name, description: "", category: source.rawValue),
            source: source
        )
    }

    func testEmptyRegistrySnapshotIsEmpty() async {
        let registry = SlashCommandRegistry()
        let snapshot = await registry.snapshot()
        XCTAssertTrue(snapshot.isEmpty)
    }

    func testCombinesMultipleSources() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubSource(items: [makeCommand(name: "a")]), id: "s1")
        await registry.register(
            StubSource(items: [makeCommand(name: "b", source: .builtin)]), id: "s2"
        )
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.map(\.command.name).sorted(), ["a", "b"])
    }

    func testSortByPriorityThenName() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubSource(items: [
            makeCommand(name: "z", source: .skill),
            makeCommand(name: "a", source: .userFile),
            makeCommand(name: "m", source: .builtin),
        ]), id: "s")
        let snapshot = await registry.snapshot()
        // builtin(0) < userFile(1) < skill(3)
        XCTAssertEqual(snapshot.map(\.command.name), ["m", "a", "z"])
    }

    func testDedupesByID() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubSource(items: [
            makeCommand(name: "x"),
            makeCommand(name: "x"),
        ]), id: "s")
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.count, 1)
    }

    func testKeepsCommandsWithSameNameDifferentSources() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubSource(items: [
            makeCommand(name: "help", source: .builtin),
            makeCommand(name: "help", source: .userFile),
        ]), id: "s")
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.count, 2)
    }

    func testRegisterInvalidatesCache() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubSource(items: [makeCommand(name: "a")]), id: "s1")
        _ = await registry.snapshot()
        await registry.register(StubSource(items: [makeCommand(name: "b")]), id: "s2")
        let after = await registry.snapshot()
        XCTAssertEqual(after.count, 2)
    }

    func testUnregisterRemovesItsCommands() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubSource(items: [makeCommand(name: "a")]), id: "s1")
        await registry.register(StubSource(items: [makeCommand(name: "b")]), id: "s2")
        _ = await registry.snapshot()
        await registry.unregister(id: "s1")
        let after = await registry.snapshot()
        XCTAssertEqual(after.map(\.command.name), ["b"])
    }

    func testRefreshBroadcastsToObservers() async throws {
        let registry = SlashCommandRegistry()
        let stream = await registry.observe()
        await registry.register(StubSource(items: [makeCommand(name: "x")]), id: "s")
        await registry.refresh()
        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertEqual(received?.first?.command.name, "x")
    }
}
