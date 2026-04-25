@testable import MaestroCore
import XCTest

final class DataMigratorTests: XCTestCase {
    private actor StubMigrator: DataMigrator {
        let from: SchemaVersion
        let to: SchemaVersion
        var didRun: Bool = false
        let shouldThrow: Bool

        init(from: Int, to: Int, shouldThrow: Bool = false) {
            self.from = SchemaVersion(from)
            self.to = SchemaVersion(to)
            self.shouldThrow = shouldThrow
        }

        func migrate() async throws {
            didRun = true
            if shouldThrow { throw TestError.boom }
        }

        enum TestError: Error { case boom }
    }

    private var tempRoot: URL!
    private var versionFile: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "DataMigratorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        versionFile = tempRoot.appending(path: "version.json", directoryHint: .notDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testFreshAppHasV0() async throws {
        let coord = DataMigrationCoordinator(versionFile: versionFile, target: .v0)
        let current = try await coord.currentVersion()
        XCTAssertEqual(current, .v0)
    }

    func testNoMigrationWhenAlreadyAtTarget() async throws {
        let coord = DataMigrationCoordinator(versionFile: versionFile, target: .v0)
        let executed = try await coord.migrateIfNeeded()
        XCTAssertTrue(executed.isEmpty)
    }

    func testRunsSequentialMigrations() async throws {
        let coord = DataMigrationCoordinator(
            versionFile: versionFile, target: SchemaVersion(2)
        )
        let m1 = StubMigrator(from: 0, to: 1)
        let m2 = StubMigrator(from: 1, to: 2)
        await coord.register(m1)
        await coord.register(m2)
        let executed = try await coord.migrateIfNeeded()
        XCTAssertEqual(executed, [SchemaVersion(1), SchemaVersion(2)])
        let r1 = await m1.didRun
        let r2 = await m2.didRun
        XCTAssertTrue(r1)
        XCTAssertTrue(r2)
        let after = try await coord.currentVersion()
        XCTAssertEqual(after, SchemaVersion(2))
    }

    func testThrowsOnMissingMigrator() async throws {
        let coord = DataMigrationCoordinator(
            versionFile: versionFile, target: SchemaVersion(2)
        )
        await coord.register(StubMigrator(from: 0, to: 1))
        // missing 1→2
        do {
            _ = try await coord.migrateIfNeeded()
            XCTFail("should throw")
        } catch DataMigrationError.missingMigrator(let from) {
            XCTAssertEqual(from, SchemaVersion(1))
        }
    }

    func testThrowsOnInvalidStep() async throws {
        let coord = DataMigrationCoordinator(
            versionFile: versionFile, target: SchemaVersion(2)
        )
        // 0 → 2 is invalid (must be +1)
        await coord.register(StubMigrator(from: 0, to: 2))
        do {
            _ = try await coord.migrateIfNeeded()
            XCTFail("should throw")
        } catch DataMigrationError.invalidStep {
            // ok
        }
    }

    func testFailedMigrationStopsAndPreservesProgress() async throws {
        let coord = DataMigrationCoordinator(
            versionFile: versionFile, target: SchemaVersion(3)
        )
        await coord.register(StubMigrator(from: 0, to: 1))
        await coord.register(StubMigrator(from: 1, to: 2, shouldThrow: true))
        await coord.register(StubMigrator(from: 2, to: 3))
        do {
            _ = try await coord.migrateIfNeeded()
            XCTFail("should throw")
        } catch {
            // ok
        }
        // 1단계는 성공 + 디스크에 저장됨
        let after = try await coord.currentVersion()
        XCTAssertEqual(after, SchemaVersion(1))
    }
}
