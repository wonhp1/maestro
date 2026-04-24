@testable import MaestroCore
import XCTest

final class JSONLAppenderTests: XCTestCase {
    private struct Entry: Codable, Equatable, Sendable {
        let n: Int
        let label: String
    }

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "jsonl-appender")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testAppendCreatesFileAndWritesLine() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        try await appender.append(Entry(n: 1, label: "a"))
        let contents = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(contents.contains(#""n":1"#))
        XCTAssertTrue(contents.hasSuffix("\n"), "각 라인은 \\n 으로 끝남")
    }

    func testAppendManyYieldsOneLinePerEntry() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        try await appender.appendAll([
            Entry(n: 1, label: "a"),
            Entry(n: 2, label: "b"),
            Entry(n: 3, label: "c"),
        ])
        let contents = try String(contentsOf: path, encoding: .utf8)
        XCTAssertEqual(contents.filter { $0 == "\n" }.count, 3)
    }

    func testSequentialAppendsPreserveOrder() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        for index in 0..<10 {
            try await appender.append(Entry(n: index, label: "x"))
        }
        let lines = try String(contentsOf: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 10)
        for (index, line) in lines.enumerated() {
            XCTAssertTrue(line.contains("\"n\":\(index)"))
        }
    }

    func testAppendCreatesParentDir() async throws {
        let nested = tempDir.appending(path: "deep/nested/log.jsonl")
        let appender = JSONLAppender<Entry>(path: nested)
        try await appender.append(Entry(n: 0, label: "deep"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testCurrentByteSizeReflectsAppends() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        let size0 = try await appender.currentByteSize()
        XCTAssertEqual(size0, 0)
        try await appender.append(Entry(n: 1, label: "a"))
        let size1 = try await appender.currentByteSize()
        XCTAssertGreaterThan(size1, 0)
        try await appender.append(Entry(n: 2, label: "b"))
        let size2 = try await appender.currentByteSize()
        XCTAssertGreaterThan(size2, size1)
    }

    func testAppendEmptyArrayIsNoOp() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        try await appender.appendAll([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testConcurrentAppendsProduceValidLines() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        // actor 는 동시 호출을 직렬화 — 100 병렬 중에도 라인이 찢어지지 않아야 한다.
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    try? await appender.append(Entry(n: index, label: "c"))
                }
            }
        }
        let contents = try String(contentsOf: path, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 100, "100 번 append → 정확히 100 라인")
        for line in lines {
            XCTAssertNoThrow(
                try JSONDecoder.maestro.decode(Entry.self, from: Data(line.utf8)),
                "모든 라인이 온전한 JSON"
            )
        }
    }

    func testAppendCreatesFileWith0600Permissions() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        try await appender.append(Entry(n: 1, label: "p"))
        let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)
    }

    func testCloseAllowsHandleReopen() async throws {
        let path = tempDir.appending(path: "log.jsonl")
        let appender = JSONLAppender<Entry>(path: path)
        try await appender.append(Entry(n: 1, label: "a"))
        await appender.close()
        // 닫은 후에도 append 가 정상 복구
        try await appender.append(Entry(n: 2, label: "b"))
        let contents = try String(contentsOf: path, encoding: .utf8)
        XCTAssertEqual(
            contents.split(separator: "\n", omittingEmptySubsequences: true).count,
            2
        )
    }
}
