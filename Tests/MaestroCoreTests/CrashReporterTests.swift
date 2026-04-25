@testable import MaestroCore
import XCTest

final class CrashReporterTests: XCTestCase {
    private var tempRoot: URL!
    private var reporter: CrashReporter!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "CrashReporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        reporter = CrashReporter(directory: tempRoot, appVersion: "0.1.0")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testRecordWritesAtomicFile() throws {
        let report = CrashReport(
            occurredAt: Date(timeIntervalSince1970: 1000),
            appVersion: "0.1.0",
            kind: .exception,
            message: "boom",
            stackTrace: ["frame1", "frame2"]
        )
        let url = try reporter.record(report)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoadPendingReportsRoundtrip() throws {
        let r1 = CrashReport(
            occurredAt: Date(), appVersion: "0.1.0", kind: .exception,
            message: "a", stackTrace: []
        )
        let r2 = CrashReport(
            occurredAt: Date(), appVersion: "0.1.0", kind: .signal,
            message: "b", stackTrace: ["x"]
        )
        try reporter.record(r1)
        try reporter.record(r2)
        let loaded = try reporter.loadPendingReports()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(Set(loaded.map(\.message)), ["a", "b"])
    }

    func testEmptyDirectoryYieldsEmpty() throws {
        let loaded = try reporter.loadPendingReports()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDismissRemovesSingleReport() throws {
        let r = CrashReport(
            occurredAt: Date(), appVersion: "0.1.0", kind: .exception,
            message: "x", stackTrace: []
        )
        try reporter.record(r)
        try reporter.dismiss(r.id)
        XCTAssertTrue(try reporter.loadPendingReports().isEmpty)
    }

    func testDismissAllRemovesAllReports() throws {
        for _ in 0..<3 {
            try reporter.record(CrashReport(
                occurredAt: Date(), appVersion: "0.1.0", kind: .exception,
                message: "x", stackTrace: []
            ))
        }
        try reporter.dismissAll()
        XCTAssertTrue(try reporter.loadPendingReports().isEmpty)
    }

    func testCorruptFileSkipped() throws {
        try reporter.ensureDirectoryExists()
        let bogus = tempRoot.appending(path: "crash-bad.json", directoryHint: .notDirectory)
        try Data("not json".utf8).write(to: bogus)
        let goodReport = CrashReport(
            occurredAt: Date(), appVersion: "0.1.0", kind: .exception,
            message: "good", stackTrace: []
        )
        try reporter.record(goodReport)
        let loaded = try reporter.loadPendingReports()
        XCTAssertEqual(loaded.map(\.message), ["good"])
    }
}
