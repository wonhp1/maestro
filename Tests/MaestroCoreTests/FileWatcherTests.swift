@testable import MaestroCore
import XCTest

final class FileWatcherTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "file-watcher")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testWriteEmitsWriteCompleted() async throws {
        let path = tempDir.appending(path: "f.txt")
        FileManager.default.createFile(atPath: path.path, contents: Data("seed".utf8))

        let stream = FileWatcher.events(for: path)

        let consumer = Task {
            for await event in stream where event == .writeCompleted {
                return
            }
        }

        // 짧은 대기 후 파일에 append — write 이벤트 유도
        try await Task.sleep(nanoseconds: 50_000_000)
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\nmore".utf8))
        try handle.close()

        try await withTimeout(seconds: 2) { await consumer.value }
    }

    func testStreamFinishesImmediatelyForMissingFile() async throws {
        let missing = tempDir.appending(path: "does-not-exist.txt")
        let stream = FileWatcher.events(for: missing)
        var collected: [FileWatchEvent] = []
        for await event in stream {
            collected.append(event)
        }
        XCTAssertTrue(collected.isEmpty, "없는 파일은 즉시 finish")
    }

    func testRenameFinishesStream() async throws {
        let path = tempDir.appending(path: "to-rename.txt")
        FileManager.default.createFile(atPath: path.path, contents: Data("x".utf8))

        let stream = FileWatcher.events(for: path)

        let consumer = Task {
            var events: [FileWatchEvent] = []
            for await event in stream {
                events.append(event)
            }
            return events
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let renamed = tempDir.appending(path: "renamed.txt")
        try FileManager.default.moveItem(at: path, to: renamed)

        let received = try await withTimeout(seconds: 2) { await consumer.value }
        XCTAssertTrue(
            received.contains(.renamed),
            "rename 이벤트 수신 필요 (received: \(received))"
        )
    }

    func testDeleteFinishesStream() async throws {
        let path = tempDir.appending(path: "to-delete.txt")
        FileManager.default.createFile(atPath: path.path, contents: Data("x".utf8))

        let stream = FileWatcher.events(for: path)

        let consumer = Task {
            var events: [FileWatchEvent] = []
            for await event in stream {
                events.append(event)
            }
            return events
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        try FileManager.default.removeItem(at: path)

        let received = try await withTimeout(seconds: 2) { await consumer.value }
        XCTAssertTrue(
            received.contains(.deleted),
            "delete 이벤트 수신 필요 (received: \(received))"
        )
    }

    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TestTimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private struct TestTimeoutError: Error {}
}
