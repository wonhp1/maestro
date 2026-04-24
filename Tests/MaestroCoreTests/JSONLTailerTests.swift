@testable import MaestroCore
import XCTest

final class JSONLTailerTests: XCTestCase {
    private struct Entry: Codable, Equatable, Sendable {
        let n: Int
    }

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "jsonl-tailer")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testTailerYieldsNewAppendsFromTheEnd() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        try await appender.append(Entry(n: 0))  // 기존 내용

        let tailer = JSONLTailer<Entry>(path: path)
        var received: [Entry] = []

        let stream = tailer.events()  // fromByteOffset: nil → 끝부터

        let consumer = Task {
            var collected: [Entry] = []
            for try await event in stream {
                collected.append(event)
                if collected.count >= 3 { break }
            }
            return collected
        }

        // 비동기 append 후 이벤트 발생 유도
        try await Task.sleep(nanoseconds: 50_000_000)
        try await appender.append(Entry(n: 1))
        try await appender.append(Entry(n: 2))
        try await appender.append(Entry(n: 3))

        received = try await withTimeout(seconds: 2) { try await consumer.value }
        XCTAssertEqual(received, [Entry(n: 1), Entry(n: 2), Entry(n: 3)])
    }

    func testTailerFromOffsetZeroEmitsHistory() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        try await appender.appendAll([Entry(n: 10), Entry(n: 20), Entry(n: 30)])

        let tailer = JSONLTailer<Entry>(path: path)
        let stream = tailer.events(fromByteOffset: 0)

        let consumer = Task {
            var collected: [Entry] = []
            for try await event in stream {
                collected.append(event)
                if collected.count >= 3 { break }
            }
            return collected
        }

        let received = try await withTimeout(seconds: 2) { try await consumer.value }
        XCTAssertEqual(received, [Entry(n: 10), Entry(n: 20), Entry(n: 30)])
    }

    // MARK: Test helper — timeout

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
