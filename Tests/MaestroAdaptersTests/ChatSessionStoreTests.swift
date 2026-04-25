import Foundation
import MaestroAdapters
@testable import MaestroCore
import XCTest

@MainActor
final class ChatSessionStoreTests: XCTestCase {
    private var tempRoot: URL!

    // CI Xcode 16.X 의 더 엄격한 isolation: setUpWithError 는 nonisolated 컨텍스트 →
    // @MainActor 격리된 tempRoot 변경 불가. async variant 로 MainActor hop.
    override func setUp() async throws {
        tempRoot = try TestSupport.makeTempDirectory()
    }

    override func tearDown() async throws {
        TestSupport.removeTempDirectory(tempRoot)
    }

    private func makeFolder() -> FolderRegistration {
        FolderRegistration(
            displayName: "Test",
            path: tempRoot,
            adapterId: AdapterID(rawValue: "mock")
        )
    }

    private func makeStore() -> (ChatSessionStore, AgentStatusStore) {
        let statusStore = AgentStatusStore()
        let store = ChatSessionStore(
            factory: { folder in
                let adapter = MockAdapter()
                let session = try await adapter.createSession(folderPath: folder.path)
                return try ChatViewModel(adapter: adapter, session: session)
            },
            statusStore: statusStore
        )
        return (store, statusStore)
    }

    func testEnsureSessionCreatesAndCachesViewModel() async throws {
        let (store, _) = makeStore()
        let folder = makeFolder()
        let vm = await store.ensureSession(for: folder)
        XCTAssertNotNil(vm)
        XCTAssertNotNil(store.cached(for: folder.id))
    }

    func testEnsureSessionReusesCachedInstance() async throws {
        let (store, _) = makeStore()
        let folder = makeFolder()
        let vm1 = await store.ensureSession(for: folder)
        let vm2 = await store.ensureSession(for: folder)
        XCTAssertTrue(vm1 === vm2, "cached instance should be reused")
    }

    func testEnsureSessionUpdatesAgentStatusToIdle() async throws {
        let (store, statusStore) = makeStore()
        let folder = makeFolder()
        _ = await store.ensureSession(for: folder)
        if case .idle = statusStore.status(for: folder.id) {
            // ok
        } else {
            XCTFail("expected idle status")
        }
    }

    func testEvictRemovesCacheAndSetsOffline() async throws {
        let (store, statusStore) = makeStore()
        let folder = makeFolder()
        _ = await store.ensureSession(for: folder)
        store.evict(folderID: folder.id)
        XCTAssertNil(store.cached(for: folder.id))
        XCTAssertEqual(statusStore.status(for: folder.id), .offline)
    }

    func testFactoryFailureIsCapturedInLastErrors() async throws {
        let statusStore = AgentStatusStore()
        let store = ChatSessionStore(
            factory: { _ in
                throw AdapterError.notInstalled(adapterId: "test")
            },
            statusStore: statusStore
        )
        let folder = makeFolder()
        let vm = await store.ensureSession(for: folder)
        XCTAssertNil(vm)
        XCTAssertNotNil(store.lastErrors[folder.id])
        if case .error = statusStore.status(for: folder.id) {
            // ok
        } else {
            XCTFail("expected error status")
        }
    }

    func testConcurrentEnsureReturnsSameInstance() async throws {
        let (store, _) = makeStore()
        let folder = makeFolder()
        async let vm1 = store.ensureSession(for: folder)
        async let vm2 = store.ensureSession(for: folder)
        let (a, b) = await (vm1, vm2)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b, "concurrent calls should converge to one instance")
    }

    func testConcurrentEnsureSurfacesFailureToBothCallers() async throws {
        // single-flight + 실패 전파 검증 (must-fix A2/PERF-1)
        let statusStore = AgentStatusStore()
        let store = ChatSessionStore(
            factory: { _ in
                try? await Task.sleep(nanoseconds: 50_000_000)
                throw AdapterError.notInstalled(adapterId: "x")
            },
            statusStore: statusStore
        )
        let folder = makeFolder()
        async let a = store.ensureSession(for: folder)
        async let b = store.ensureSession(for: folder)
        let (resultA, resultB) = await (a, b)
        XCTAssertNil(resultA)
        XCTAssertNil(resultB)
        // 두 caller 모두 lastErrors 가 채워진 상태에서 nil 을 받아야 함
        XCTAssertNotNil(store.lastErrors[folder.id])
    }

    func testEvictAllClearsEverything() async throws {
        let (store, _) = makeStore()
        let f1 = makeFolder()
        let f2 = makeFolder()
        _ = await store.ensureSession(for: f1)
        _ = await store.ensureSession(for: f2)
        store.evictAll()
        XCTAssertNil(store.cached(for: f1.id))
        XCTAssertNil(store.cached(for: f2.id))
    }
}
