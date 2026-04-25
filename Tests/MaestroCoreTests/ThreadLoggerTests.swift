import Foundation
@testable import MaestroCore
import XCTest

final class ThreadLoggerTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppSupportPaths!

    override func setUpWithError() throws {
        tempRoot = try TestSupport.makeTempDirectory()
        paths = AppSupportPaths(root: tempRoot)
        try paths.ensureAllDirectoriesExist()
    }

    override func tearDownWithError() throws {
        TestSupport.removeTempDirectory(tempRoot)
    }

    private func makeEnvelope(thread: ThreadID, body: String = "x") -> MessageEnvelope {
        MessageEnvelope.task(
            from: AgentID(rawValue: "alice"),
            to: AgentID(rawValue: "bob"),
            body: body,
            thread: thread
        )
    }

    func testLogAppendsSingleEnvelopeAsJSONLLine() async throws {
        let logger = ThreadLogger(paths: paths)
        let thread = ThreadID.new()
        let envelope = makeEnvelope(thread: thread, body: "hi")

        try await logger.log(envelope)
        await logger.closeAll()

        let path = paths.threadFile(id: thread)
        let content = try String(contentsOf: path, encoding: .utf8)
        let lines = content.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains(envelope.id.rawValue))
        XCTAssertTrue(lines[0].contains("\"body\":\"hi\""))
    }

    func testLogMultipleEnvelopesAppendsInOrder() async throws {
        let logger = ThreadLogger(paths: paths)
        let thread = ThreadID.new()
        for i in 0..<5 {
            try await logger.log(makeEnvelope(thread: thread, body: "msg\(i)"))
        }
        await logger.closeAll()

        let path = paths.threadFile(id: thread)
        let content = try String(contentsOf: path, encoding: .utf8)
        let lines = content.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 5)
        for i in 0..<5 {
            XCTAssertTrue(String(lines[i]).contains("msg\(i)"))
        }
    }

    func testDifferentThreadsGetSeparateFiles() async throws {
        let logger = ThreadLogger(paths: paths)
        let t1 = ThreadID.new()
        let t2 = ThreadID.new()
        try await logger.log(makeEnvelope(thread: t1, body: "in t1"))
        try await logger.log(makeEnvelope(thread: t2, body: "in t2"))
        await logger.closeAll()

        let c1 = try String(contentsOf: paths.threadFile(id: t1), encoding: .utf8)
        let c2 = try String(contentsOf: paths.threadFile(id: t2), encoding: .utf8)
        XCTAssertTrue(c1.contains("in t1"))
        XCTAssertFalse(c1.contains("in t2"))
        XCTAssertTrue(c2.contains("in t2"))
        XCTAssertFalse(c2.contains("in t1"))
    }

    func testLogAllRejectsMixedThreadIds() async throws {
        let logger = ThreadLogger(paths: paths)
        let t1 = ThreadID.new()
        let t2 = ThreadID.new()
        let envs = [
            makeEnvelope(thread: t1, body: "ok"),
            makeEnvelope(thread: t2, body: "alien"),
        ]
        do {
            try await logger.logAll(envs)
            XCTFail("expected mixedThreads error")
        } catch let error as ThreadLoggerError {
            guard case .mixedThreads = error else {
                XCTFail("wrong: \(error)")
                return
            }
        }
    }

    // MARK: - LRU eviction (Phase 11 perf must-fix)

    func testAppenderCacheRespectsMaxOpenLimit() async throws {
        let logger = ThreadLogger(paths: paths, maxOpenAppenders: 3)
        // 5개 thread 사용 → 캐시는 최대 3개만 유지
        for _ in 0..<5 {
            try await logger.log(makeEnvelope(thread: ThreadID.new()))
        }
        let count = await logger.openAppenderCount
        XCTAssertEqual(count, 3, "LRU cap should evict older appenders")
        await logger.closeAll()
    }

    func testCloseAndReLogStillAppendsNotTruncates() async throws {
        let logger = ThreadLogger(paths: paths)
        let thread = ThreadID.new()
        try await logger.log(makeEnvelope(thread: thread, body: "first"))
        await logger.closeAll()

        // 같은 thread 에 재로그
        try await logger.log(makeEnvelope(thread: thread, body: "second"))
        await logger.closeAll()

        let path = paths.threadFile(id: thread)
        let content = try String(contentsOf: path, encoding: .utf8)
        let lines = content.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2, "re-open should append, not truncate")
        XCTAssertTrue(content.contains("first"))
        XCTAssertTrue(content.contains("second"))
    }

    func testThreadFileHas0600Permissions() async throws {
        let logger = ThreadLogger(paths: paths)
        let thread = ThreadID.new()
        try await logger.log(makeEnvelope(thread: thread))
        await logger.closeAll()

        let path = paths.threadFile(id: thread)
        let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
        let posix = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(posix, 0o600)
    }
}
