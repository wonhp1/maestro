@testable import MaestroCore
import XCTest

@MainActor
final class MenuActionRouterTests: XCTestCase {
    private actor Recorder {
        var calls: [String] = []
        func record(_ tag: String) { calls.append(tag) }
        func snapshot() -> [String] { calls }
    }

    func testHandlersAreCalledWhenRegistered() async {
        let recorder = Recorder()
        let router = MenuActionRouter()
        router.onAddFolder = { await recorder.record("add") }
        router.onOpenCommandPalette = { await recorder.record("palette") }
        router.onRevealDataFolder = { await recorder.record("reveal") }

        router.addFolder()
        router.openCommandPalette()
        router.revealDataFolder()

        // Task spawn — yield until processed
        for _ in 0..<10 {
            await Task.yield()
            let calls = await recorder.snapshot()
            if calls.count == 3 { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let calls = await recorder.snapshot()
        XCTAssertEqual(Set(calls), ["add", "palette", "reveal"])
    }

    func testUnregisteredHandlersAreNoop() {
        let router = MenuActionRouter()
        // 등록 없이 호출 — crash 없이 통과해야 함
        router.addFolder()
        router.openCommandPalette()
        router.revealDataFolder()
        router.openPreferences()
        router.exportDiagnostics()
        router.openHelp()
        router.deleteSelectedFolder()
    }

    func testDeleteRespectsCanDeleteFlag() async {
        let recorder = Recorder()
        let router = MenuActionRouter()
        router.onDeleteSelectedFolder = { await recorder.record("delete") }
        router.canDeleteSelectedFolder = false
        router.deleteSelectedFolder()
        await Task.yield()
        let none = await recorder.snapshot()
        XCTAssertEqual(none, [], "canDelete=false 시 핸들러 미호출")

        router.canDeleteSelectedFolder = true
        router.deleteSelectedFolder()
        for _ in 0..<10 {
            await Task.yield()
            let calls = await recorder.snapshot()
            if !calls.isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let after = await recorder.snapshot()
        XCTAssertEqual(after, ["delete"])
    }
}
