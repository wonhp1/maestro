@testable import MaestroCore
import XCTest

final class AdapterRegistryTests: XCTestCase {
    func testEmptyRegistryHasZeroCountAndNoIds() async {
        let registry = AdapterRegistry()
        let count = await registry.count
        let ids = await registry.adapterIds()
        XCTAssertEqual(count, 0)
        XCTAssertTrue(ids.isEmpty)
    }

    func testRegisterAndRetrieveByID() async throws {
        let registry = AdapterRegistry()
        let adapter = TinyAdapter(idValue: "alpha")
        try await registry.register(adapter)
        let count = await registry.count
        XCTAssertEqual(count, 1)
        let retrieved = await registry.adapter(for: "alpha")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "alpha")
    }

    func testRegisterRejectsDuplicateByDefault() async throws {
        // Phase 4 must-fix: 기본은 silent replacement 차단.
        let registry = AdapterRegistry()
        try await registry.register(TinyAdapter(idValue: "x"))
        do {
            _ = try await registry.register(TinyAdapter(idValue: "x"))
            XCTFail("expected alreadyRegistered")
        } catch let err as AdapterRegistryError {
            XCTAssertEqual(err, .alreadyRegistered(id: "x"))
        }
    }

    func testRegisterReplacesWhenExplicitlyAllowed() async throws {
        let registry = AdapterRegistry()
        try await registry.register(TinyAdapter(idValue: "x"))
        let wasReplaced = try await registry.register(
            TinyAdapter(idValue: "x"),
            replacingExisting: true
        )
        XCTAssertTrue(wasReplaced)
        let count = await registry.count
        XCTAssertEqual(count, 1)
    }

    func testRegisterFirstTimeReturnsFalseForReplaced() async throws {
        let registry = AdapterRegistry()
        let wasReplaced = try await registry.register(TinyAdapter(idValue: "x"))
        XCTAssertFalse(wasReplaced)
    }

    func testUnregisterRemoves() async throws {
        let registry = AdapterRegistry()
        try await registry.register(TinyAdapter(idValue: "x"))
        let removed = await registry.unregister(id: "x")
        XCTAssertTrue(removed)
        let count = await registry.count
        XCTAssertEqual(count, 0)
    }

    func testUnregisterUnknownReturnsFalse() async {
        let registry = AdapterRegistry()
        let removed = await registry.unregister(id: "nope")
        XCTAssertFalse(removed)
    }

    func testAdapterIdsReturnedSorted() async throws {
        let registry = AdapterRegistry()
        try await registry.register(TinyAdapter(idValue: "charlie"))
        try await registry.register(TinyAdapter(idValue: "alpha"))
        try await registry.register(TinyAdapter(idValue: "bravo"))
        let ids = await registry.adapterIds()
        XCTAssertEqual(ids, ["alpha", "bravo", "charlie"])
    }

    func testDetectAllRunsOnAllRegistered() async throws {
        let registry = AdapterRegistry()
        try await registry.register(TinyAdapter(idValue: "alpha", installedVersion: "1.0"))
        try await registry.register(TinyAdapter(idValue: "bravo", installedVersion: nil))
        let results = await registry.detectAll()
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results["alpha"]?.version, "1.0")
        XCTAssertEqual(results["bravo"]?.isInstalled, false)
    }

    /// Phase 4 must-fix: detectAll 의 병렬성을 wall-clock 으로 검증.
    /// 각 어댑터의 detect 가 200ms 슬립한다고 가정.
    /// 5개 등록 시 직렬이면 1000ms+, 병렬이면 ~250ms.
    func testDetectAllRunsAdaptersInParallel() async throws {
        let registry = AdapterRegistry()
        for idx in 0..<5 {
            try await registry.register(SlowAdapter(idValue: "slow-\(idx)", delayMs: 200))
        }
        let start = Date()
        let results = await registry.detectAll()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(results.count, 5)
        XCTAssertLessThan(elapsed, 0.6, "detectAll 가 직렬로 실행됨 (\(elapsed)s)")
    }
}

/// 의도적으로 지연되는 어댑터 — 병렬성 검증용.
private struct SlowAdapter: AgentAdapter {
    static var id: String { "slow-static-unused" }
    static let displayName = "Slow"

    let dynamicId: String
    let delayMs: UInt64

    init(idValue: String, delayMs: UInt64) {
        self.dynamicId = idValue
        self.delayMs = delayMs
    }

    var id: String { dynamicId }
    var displayName: String { Self.displayName }
    var iconName: String { "tortoise" }

    func detect() async -> AdapterDetection {
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
        return AdapterDetection(
            isInstalled: true,
            version: "1.0",
            executablePath: nil,
            detectedAt: Date()
        )
    }

    func createSession(folderPath: URL) async throws -> Session {
        Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "x"),
            adapterId: try AdapterID.validated(rawValue: "slow"),
            folderPath: folderPath,
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
    }

    func destroySession(_ id: SessionID) async throws {}

    func sendMessage(
        _ envelope: MessageEnvelope, in session: Session
    ) async throws -> MessageEnvelope {
        envelope
    }
}

// MARK: - Test fixture

/// Identifier-validated id 를 가진 최소 어댑터.
/// `installedVersion=nil` 이면 detect 가 notInstalled 반환.
private struct TinyAdapter: AgentAdapter {
    static var id: String { "tiny-static-unused" }
    static let displayName = "Tiny"

    let dynamicId: String
    let installedVersion: String?

    init(idValue: String, installedVersion: String? = "1.0.0") {
        self.dynamicId = idValue
        self.installedVersion = installedVersion
    }

    var id: String { dynamicId }
    var displayName: String { Self.displayName }
    var iconName: String { "ant" }

    func detect() async -> AdapterDetection {
        guard let version = installedVersion else { return .notInstalled() }
        return AdapterDetection(
            isInstalled: true,
            version: version,
            executablePath: URL(fileURLWithPath: "/tmp/\(dynamicId)"),
            detectedAt: Date()
        )
    }

    func createSession(folderPath: URL) async throws -> Session {
        Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "x"),
            adapterId: try AdapterID.validated(rawValue: "tiny"),
            folderPath: folderPath,
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
    }

    func destroySession(_ id: SessionID) async throws {}

    func sendMessage(
        _ envelope: MessageEnvelope, in session: Session
    ) async throws -> MessageEnvelope {
        envelope
    }
}
