@testable import MaestroCore
import XCTest

@MainActor
final class PrivacyAcknowledgementTests: XCTestCase {
    private var tempRoot: URL!
    private var path: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "PrivacyAckTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        path = tempRoot.appending(path: "preferences.json", directoryHint: .notDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testDefaultIsFalse() async {
        let store = PreferencesStore(path: path, autosaveDebounceNanos: 0)
        await store.bootstrap()
        XCTAssertFalse(store.snapshot.privacyPolicyAccepted)
    }

    func testSetTrueAndPersists() async throws {
        let store1 = PreferencesStore(path: path, autosaveDebounceNanos: 0)
        await store1.bootstrap()
        store1.setPrivacyPolicyAccepted(true)
        await store1.flush()

        let store2 = PreferencesStore(path: path)
        await store2.bootstrap()
        XCTAssertTrue(store2.snapshot.privacyPolicyAccepted)
    }
}
