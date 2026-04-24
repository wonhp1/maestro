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

    func testMalformedLineFinishesStreamWithError() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        // 올바른 Entry 1건 + 손상된 JSON 1건.
        let valid = try JSONEncoder.maestro.encode(Entry(n: 1))
        var data = Data()
        data.append(valid)
        data.append(0x0A)
        data.append(Data("not json {]\n".utf8))
        try data.write(to: path)

        let tailer = JSONLTailer<Entry>(path: path)
        let stream = tailer.events(fromByteOffset: 0)

        // 타임아웃 포함 수집 — 손상 라인에 부딪히면 stream 이 decodingFailed 로 종료.
        do {
            _ = try await withTimeout(seconds: 2) {
                var collected: [Entry] = []
                for try await event in stream {
                    collected.append(event)
                }
                return collected
            }
            XCTFail("손상된 라인은 decodingFailed 로 stream 종료")
        } catch let err as PersistenceError {
            if case .decodingFailed = err { /* pass */ } else {
                XCTFail("예상과 다른 에러: \(err)")
            }
        } catch {
            XCTFail("PersistenceError 기대: \(error)")
        }
    }

    func testPartialLineAtEOFIsNotYielded() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        // 완성된 라인 1건 + 개행 없이 끝나는 파편.
        let valid = try JSONEncoder.maestro.encode(Entry(n: 99))
        var data = Data()
        data.append(valid)
        data.append(0x0A)
        data.append(Data(#"{"n":"#.utf8)) // 불완전
        try data.write(to: path)

        let tailer = JSONLTailer<Entry>(path: path)
        let stream = tailer.events(fromByteOffset: 0)

        // 유한 수집: 첫 이벤트 1건만 받고 즉시 종료. 파편은 영원히 안 옴 → break 로 끝냄.
        let collected: [Entry] = try await withTimeout(seconds: 2) {
            var collected: [Entry] = []
            for try await event in stream {
                collected.append(event)
                break  // 1건 받으면 즉시 종료 (파편 대기 방지)
            }
            return collected
        }
        XCTAssertEqual(collected, [Entry(n: 99)])
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
