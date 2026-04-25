@testable import MaestroCore
import XCTest

final class SlashCommandWatcherTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "SlashCommandWatcherTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func write(_ name: String, _ content: String = "x") throws {
        let url = tempRoot.appending(path: name, directoryHint: .notDirectory)
        try content.data(using: .utf8)!.write(to: url)
    }

    func testInitialRefreshOnStart() async {
        try? write("a.md")
        let registry = SlashCommandRegistry()
        await registry.register(
            FileSlashCommandSource(directory: tempRoot), id: "file"
        )
        let watcher = SlashCommandWatcher(
            directories: [tempRoot],
            registry: registry,
            debounceNanos: 50_000_000,
            pollInterval: 60.0
        )
        await watcher.start()
        defer { Task { await watcher.stop() } }

        // start spawns drive() which calls refresh() — wait for it.
        for _ in 0..<20 {
            await Task.yield()
            let snap = await registry.snapshot()
            if !snap.isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let snap = await registry.snapshot()
        XCTAssertEqual(snap.first?.command.name, "a")
    }

    func testFileAdditionTriggersRefresh() async throws {
        let registry = SlashCommandRegistry()
        await registry.register(
            FileSlashCommandSource(directory: tempRoot), id: "file"
        )
        let watcher = SlashCommandWatcher(
            directories: [tempRoot],
            registry: registry,
            debounceNanos: 100_000_000,
            pollInterval: 60.0
        )
        await watcher.start()
        defer { Task { await watcher.stop() } }

        // 초기 refresh 끝나길 대기
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            let snap = await registry.snapshot()
            if snap.isEmpty { break }
        }

        // 파일 추가
        try write("new.md", "hello")

        // DirectoryWatcher → debounce → refresh — 최대 5초 polling
        var found = false
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let snap = await registry.snapshot()
            if snap.contains(where: { $0.command.name == "new" }) {
                found = true
                break
            }
        }
        XCTAssertTrue(found, "watcher 가 새 파일을 5초 이내 반영해야 함")
    }

    func testStopCancelsTasks() async {
        let registry = SlashCommandRegistry()
        let watcher = SlashCommandWatcher(
            directories: [tempRoot], registry: registry,
            debounceNanos: 50_000_000, pollInterval: 60.0
        )
        await watcher.start()
        await watcher.stop()
        // 두 번째 stop 호출은 안전
        await watcher.stop()
        // restart 가능
        await watcher.start()
        await watcher.stop()
    }
}
