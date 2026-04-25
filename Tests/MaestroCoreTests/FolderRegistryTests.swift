import Foundation
@testable import MaestroCore
import XCTest

final class FolderRegistryTests: XCTestCase {
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

    private func makeFolder() throws -> URL {
        let dir = tempRoot.appending(path: "project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Add

    func testAddPersistsAndReturnsRegistration() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()

        let registered = try await registry.add(
            displayName: "Project A",
            path: dir,
            adapterId: AdapterID(rawValue: "claude")
        )

        XCTAssertEqual(registered.displayName, "Project A")
        let all = await registry.list()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.foldersFile.path))
    }

    func testAddRejectsDuplicatePath() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        let adapter = AdapterID(rawValue: "claude")

        _ = try await registry.add(displayName: "First", path: dir, adapterId: adapter)
        do {
            _ = try await registry.add(displayName: "Second", path: dir, adapterId: adapter)
            XCTFail("expected duplicatePath error")
        } catch let error as FolderRegistryError {
            guard case .duplicatePath = error else {
                XCTFail("wrong error: \(error)")
                return
            }
        }
    }

    func testAddRejectsDuplicateID() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let id = FolderID.new()
        let dirA = try makeFolder()
        let dirB = try makeFolder()
        let adapter = AdapterID(rawValue: "claude")

        _ = try await registry.add(
            displayName: "A", path: dirA, adapterId: adapter, id: id
        )
        do {
            _ = try await registry.add(
                displayName: "B", path: dirB, adapterId: adapter, id: id
            )
            XCTFail("expected duplicateID")
        } catch let error as FolderRegistryError {
            guard case .duplicateID = error else {
                XCTFail("wrong error: \(error)")
                return
            }
        }
    }

    func testAddRejectsInvalidName() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        do {
            _ = try await registry.add(
                displayName: "",
                path: dir,
                adapterId: AdapterID(rawValue: "claude")
            )
            XCTFail("expected validation error")
        } catch let error as FolderRegistrationError {
            XCTAssertEqual(error, .emptyDisplayName)
        }
    }

    // MARK: - Remove / Update

    func testRemoveEliminatesFolderAndPersists() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        let r = try await registry.add(
            displayName: "X", path: dir, adapterId: AdapterID(rawValue: "claude")
        )

        try await registry.remove(id: r.id)
        let all = await registry.list()
        XCTAssertTrue(all.isEmpty)

        // 디스크 재로드 검증
        let registry2 = FolderRegistry(paths: paths)
        try await registry2.loadFromDisk()
        let all2 = await registry2.list()
        XCTAssertTrue(all2.isEmpty)
    }

    func testRemoveThrowsForUnknownID() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        do {
            try await registry.remove(id: FolderID.new())
            XCTFail("expected notFound")
        } catch let error as FolderRegistryError {
            guard case .notFound = error else {
                XCTFail("wrong error: \(error)")
                return
            }
        }
    }

    func testUpdateChangesNameAndAdapter() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        let r = try await registry.add(
            displayName: "Old", path: dir, adapterId: AdapterID(rawValue: "claude")
        )

        let updated = try await registry.update(
            id: r.id,
            displayName: "New",
            adapterId: AdapterID(rawValue: "aider")
        )
        XCTAssertEqual(updated.displayName, "New")
        XCTAssertEqual(updated.adapterId.rawValue, "aider")
    }

    func testUpdateRejectsInvalidName() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        let r = try await registry.add(
            displayName: "Old", path: dir, adapterId: AdapterID(rawValue: "claude")
        )
        do {
            _ = try await registry.update(id: r.id, displayName: "")
            XCTFail("expected emptyDisplayName")
        } catch let error as FolderRegistrationError {
            XCTAssertEqual(error, .emptyDisplayName)
        }
    }

    func testTouchUpdatesLastUsedAt() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        let r = try await registry.add(
            displayName: "X", path: dir, adapterId: AdapterID(rawValue: "claude")
        )
        XCTAssertNil(r.lastUsedAt)

        let now = Date()
        try await registry.touch(id: r.id, now: now)
        let updated = await registry.get(id: r.id)
        XCTAssertEqual(updated?.lastUsedAt, now)
    }

    // MARK: - Persistence round-trip

    func testRegistryRehydratesAcrossInstances() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dirA = try makeFolder()
        let dirB = try makeFolder()
        let dirC = try makeFolder()
        let adapter = AdapterID(rawValue: "claude")
        _ = try await registry.add(displayName: "A", path: dirA, adapterId: adapter)
        _ = try await registry.add(displayName: "B", path: dirB, adapterId: adapter)
        _ = try await registry.add(displayName: "C", path: dirC, adapterId: adapter)

        let registry2 = FolderRegistry(paths: paths)
        try await registry2.loadFromDisk()
        let all = await registry2.list()
        XCTAssertEqual(all.map(\.displayName), ["A", "B", "C"])
    }

    func testFoldersFileHas0600Permissions() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        _ = try await registry.add(
            displayName: "X", path: dir, adapterId: AdapterID(rawValue: "claude")
        )

        let attrs = try FileManager.default.attributesOfItem(atPath: paths.foldersFile.path)
        let posix = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(posix, 0o600)
    }

    // MARK: - loadFromDisk validates entries (Phase 10 security must-fix)

    func testLoadFromDiskPrunesEntriesWithMissingPath() async throws {
        // 이미 존재하지 않는 path 가 담긴 folders.json 직접 작성
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        _ = try await registry.add(
            displayName: "X", path: dir, adapterId: AdapterID(rawValue: "claude")
        )

        // 디렉토리 삭제 → 다음 load 에서 prune 되어야 함
        try FileManager.default.removeItem(at: dir)

        let registry2 = FolderRegistry(paths: paths)
        try await registry2.loadFromDisk()
        let all = await registry2.list()
        XCTAssertTrue(all.isEmpty, "deleted-path entry should be pruned on load")
        let invalidCount = await registry2.invalidEntries.count
        XCTAssertEqual(invalidCount, 1)
    }

    func testLoadFromDiskPrunesEntriesWithBidiSpoofedName() async throws {
        // Bidi 가 들어간 항목을 손으로 디스크에 주입
        let evilFolder = FolderRegistration(
            id: FolderID.new(),
            displayName: "evil\u{202E}name",
            path: tempRoot,  // 존재하는 디렉토리
            adapterId: AdapterID(rawValue: "claude")
        )
        let file = FoldersFile(version: 1, folders: [evilFolder])
        let data = try JSONEncoder.maestro.encode(file)
        try data.write(to: paths.foldersFile)

        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let all = await registry.list()
        XCTAssertTrue(all.isEmpty, "bidi-spoofed entry should be pruned")
    }

    // MARK: - changeAdapter / no-op update (test gaps)

    func testUpdateWithBothNilParamsIsNoOpButPersists() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let dir = try makeFolder()
        let r = try await registry.add(
            displayName: "X", path: dir, adapterId: AdapterID(rawValue: "claude")
        )
        let updated = try await registry.update(id: r.id)  // both nil
        XCTAssertEqual(updated.displayName, "X")
        XCTAssertEqual(updated.adapterId, r.adapterId)
    }

    // MARK: - Concurrent add (test must-fix)

    func testConcurrentAddSerializedByActor() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()

        // 10개 distinct dir 동시 add
        let dirs = try (0..<10).map { _ in try makeFolder() }
        await withTaskGroup(of: Void.self) { group in
            for dir in dirs {
                group.addTask {
                    _ = try? await registry.add(
                        displayName: dir.lastPathComponent,
                        path: dir,
                        adapterId: AdapterID(rawValue: "claude")
                    )
                }
            }
            await group.waitForAll()
        }

        let all = await registry.list()
        XCTAssertEqual(all.count, 10, "all 10 concurrent adds should succeed (actor serializes)")

        // 디스크 재로드도 일관성 있어야 함
        let registry2 = FolderRegistry(paths: paths)
        try await registry2.loadFromDisk()
        let reloaded = await registry2.list()
        XCTAssertEqual(reloaded.count, 10)
    }

    // MARK: - Events

    func testEmitsAddedEvent() async throws {
        let registry = FolderRegistry(paths: paths)
        try await registry.loadFromDisk()
        let stream = await registry.events()
        let dir = try makeFolder()

        let receivedTask = Task { () -> FolderRegistryEvent? in
            for await event in stream { return event }
            return nil
        }

        _ = try await registry.add(
            displayName: "X", path: dir, adapterId: AdapterID(rawValue: "claude")
        )

        let event = await withTaskTimeout(seconds: 2.0) { await receivedTask.value }
        guard case .added(let folder) = event else {
            XCTFail("expected .added, got \(String(describing: event))")
            return
        }
        XCTAssertEqual(folder.displayName, "X")
        receivedTask.cancel()
    }
}

// MARK: - Helpers

private func withTaskTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result: T? = await group.next().flatMap { $0 }
        group.cancelAll()
        return result
    }
}
