@testable import MaestroCore
import XCTest

@MainActor
final class CommandPaletteViewModelTests: XCTestCase {
    private struct FixedProvider: CommandProvider {
        let items: [Command]
        func commands() async -> [Command] { items }
    }

    private func makeCommand(id: String, title: String, _ counter: Counter? = nil) -> Command {
        Command(id: id, title: title, category: .system) {
            await counter?.increment()
        }
    }

    private actor Counter {
        var count: Int = 0
        func increment() { count += 1 }
        func value() -> Int { count }
    }

    private func makeViewModel() async -> (CommandPaletteViewModel, RecentCommandTracker) {
        let registry = CommandRegistry()
        let tracker = RecentCommandTracker()
        // 테스트는 debounce 0 — 즉시 search (must-fix MED-5)
        let vm = CommandPaletteViewModel(
            registry: registry, recentTracker: tracker, debounceNanos: 0
        )
        await registry.register(FixedProvider(items: [
            makeCommand(id: "open-folder", title: "open folder"),
            makeCommand(id: "open-recent", title: "open recent"),
            makeCommand(id: "settings", title: "settings"),
        ]), id: "p1")
        return (vm, tracker)
    }

    func testPresentLoadsAllCommands() async {
        let (vm, _) = await makeViewModel()
        await vm.present()
        XCTAssertTrue(vm.isPresented)
        XCTAssertEqual(vm.results.count, 3)
    }

    func testQueryFiltersResults() async throws {
        let (vm, _) = await makeViewModel()
        await vm.present()
        vm.query = "open"
        // debounce 0 + refresh — 즉시 yield 후 결과 반영
        for _ in 0..<10 {
            await Task.yield()
            if vm.results.count == 2 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(vm.results.count, 2)
    }

    func testRecentCommandsAreRetaggedToRecentCategory() async {
        let (vm, tracker) = await makeViewModel()
        tracker.record(commandID: "settings")
        await vm.present()
        XCTAssertEqual(vm.results.first?.id, "settings")
        XCTAssertEqual(vm.results.first?.category, .recent, "recent retag (must-fix MED-2)")
    }

    func testPresentTwiceDismisses() async {
        let (vm, _) = await makeViewModel()
        await vm.present()
        XCTAssertTrue(vm.isPresented)
        await vm.present()
        XCTAssertFalse(vm.isPresented, "Cmd+K toggle (must-fix MED-1)")
    }

    func testMoveSelectionWraps() async {
        let (vm, _) = await makeViewModel()
        await vm.present()
        XCTAssertEqual(vm.selectedIndex, 0)
        vm.moveSelection(by: -1)
        XCTAssertEqual(vm.selectedIndex, vm.results.count - 1)
        vm.moveSelection(by: 1)
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func testExecuteSelectedCallsHandlerAndDismisses() async {
        let counter = Counter()
        let registry = CommandRegistry()
        let tracker = RecentCommandTracker()
        let vm = CommandPaletteViewModel(registry: registry, recentTracker: tracker)
        await registry.register(FixedProvider(items: [
            makeCommand(id: "x", title: "x", counter),
        ]), id: "p")
        await vm.present()
        await vm.executeSelected()
        let count = await counter.value()
        XCTAssertEqual(count, 1)
        XCTAssertFalse(vm.isPresented)
        XCTAssertTrue(tracker.recentIDs.contains("x"))
    }

    func testRecentCommandsPrependedOnEmptyQuery() async throws {
        let (vm, tracker) = await makeViewModel()
        tracker.record(commandID: "settings")
        await vm.present()
        XCTAssertEqual(vm.results.first?.id, "settings", "recent 가 첫 번째에")
    }

    func testDismissResetsState() async {
        let (vm, _) = await makeViewModel()
        await vm.present()
        vm.query = "open"
        vm.selectedIndex = 1
        vm.dismiss()
        XCTAssertFalse(vm.isPresented)
        XCTAssertEqual(vm.query, "")
        XCTAssertEqual(vm.selectedIndex, 0)
        XCTAssertTrue(vm.results.isEmpty)
    }
}

@MainActor
final class RecentCommandTrackerTests: XCTestCase {
    func testRecordAddsToFront() {
        let tracker = RecentCommandTracker()
        tracker.record(commandID: "a")
        tracker.record(commandID: "b")
        XCTAssertEqual(tracker.recentIDs, ["b", "a"])
    }

    func testRecordSameCommandMovesToFront() {
        let tracker = RecentCommandTracker()
        tracker.record(commandID: "a")
        tracker.record(commandID: "b")
        tracker.record(commandID: "a")
        XCTAssertEqual(tracker.recentIDs, ["a", "b"])
    }

    func testCapacityCap() {
        let tracker = RecentCommandTracker(capacity: 2)
        tracker.record(commandID: "a")
        tracker.record(commandID: "b")
        tracker.record(commandID: "c")
        XCTAssertEqual(tracker.recentIDs, ["c", "b"])
    }

    func testClearEmpties() {
        let tracker = RecentCommandTracker()
        tracker.record(commandID: "a")
        tracker.clear()
        XCTAssertTrue(tracker.recentIDs.isEmpty)
    }
}
