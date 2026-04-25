@testable import MaestroCore
import XCTest

@MainActor
final class PreferencesStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var path: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "PreferencesStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        path = tempRoot.appending(path: "preferences.json", directoryHint: .notDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testDefaultsWhenFileMissing() async {
        let store = PreferencesStore(path: path)
        await store.bootstrap()
        XCTAssertFalse(store.snapshot.firstRunCompleted)
        XCTAssertTrue(store.snapshot.notificationsEnabled)
        XCTAssertEqual(store.snapshot.enabledAdapterIDs, ["claude"])
    }

    func testSetFirstRunPersists() async throws {
        let store1 = PreferencesStore(path: path, autosaveDebounceNanos: 0)
        await store1.bootstrap()
        store1.setFirstRunCompleted(true)
        await store1.flush()

        let store2 = PreferencesStore(path: path)
        await store2.bootstrap()
        XCTAssertTrue(store2.snapshot.firstRunCompleted)
    }

    func testAdapterEnabledDisabledFlow() async {
        let store = PreferencesStore(path: path, autosaveDebounceNanos: 0)
        await store.bootstrap()
        store.setAdapterEnabled("aider", enabled: true)
        XCTAssertTrue(store.snapshot.enabledAdapterIDs.contains("aider"))
        store.setAdapterEnabled("claude", enabled: false)
        XCTAssertFalse(store.snapshot.enabledAdapterIDs.contains("claude"))
        // preferred 가 disabled 되면 자동 fallback
        XCTAssertEqual(store.snapshot.preferredAdapterID, "aider")
    }

    func testSetPreferredRequiresEnabled() async {
        let store = PreferencesStore(path: path, autosaveDebounceNanos: 0)
        await store.bootstrap()
        store.setPreferredAdapter("nonexistent")
        // 미허용 어댑터는 무시
        XCTAssertEqual(store.snapshot.preferredAdapterID, "claude")
    }

    func testDispatchTimeoutClampToBounds() async {
        let store = PreferencesStore(path: path, autosaveDebounceNanos: 0)
        await store.bootstrap()
        store.setDispatchTimeoutSeconds(0)
        XCTAssertEqual(store.snapshot.dispatchTimeoutSeconds, 5)
        store.setDispatchTimeoutSeconds(100_000)
        XCTAssertEqual(store.snapshot.dispatchTimeoutSeconds, 3600)
    }

    func testCorruptFileFallsBackToDefaults() async throws {
        try Data("not json".utf8).write(to: path)
        let store = PreferencesStore(path: path)
        await store.bootstrap()
        // 손상 파일 → silently default
        XCTAssertEqual(store.snapshot, PreferencesSnapshot.default)
    }

    func testReplaceSnapshotPersists() async throws {
        let store1 = PreferencesStore(path: path, autosaveDebounceNanos: 0)
        await store1.bootstrap()
        var next = PreferencesSnapshot.default
        next.notificationsEnabled = false
        next.dispatchTimeoutSeconds = 60
        store1.replaceSnapshot(next)
        await store1.flush()

        let store2 = PreferencesStore(path: path)
        await store2.bootstrap()
        XCTAssertFalse(store2.snapshot.notificationsEnabled)
        XCTAssertEqual(store2.snapshot.dispatchTimeoutSeconds, 60)
    }
}
