@testable import MaestroCore
import XCTest

@MainActor
final class AdapterDetectionViewModelTests: XCTestCase {
    func testRefreshFetchesDetectionForAllRegisteredAdapters() async throws {
        let registry = AdapterRegistry()
        try await registry.register(
            FakeAdapter(id: "claude", isInstalled: true, version: "0.4.0")
        )
        try await registry.register(
            FakeAdapter(id: "aider", isInstalled: false, version: nil)
        )
        let viewModel = AdapterDetectionViewModel(registry: registry)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.detections.count, 2)
        XCTAssertEqual(viewModel.detection(for: "claude")?.isInstalled, true)
        XCTAssertEqual(viewModel.detection(for: "claude")?.version, "0.4.0")
        XCTAssertEqual(viewModel.detection(for: "aider")?.isInstalled, false)
    }

    func testRefreshSetsLoadingFlagDuringExecution() async throws {
        let registry = AdapterRegistry()
        try await registry.register(
            FakeAdapter(id: "claude", isInstalled: true, version: "0.4.0")
        )
        let viewModel = AdapterDetectionViewModel(registry: registry)
        XCTAssertFalse(viewModel.isDetecting)
        await viewModel.refresh()
        XCTAssertFalse(viewModel.isDetecting) // 끝나면 false
    }

    func testInstallationHintReturnsKnownCommandsForKnownAdapters() {
        XCTAssertNotNil(AdapterDetectionViewModel.installationHint(for: "claude"))
        XCTAssertNotNil(AdapterDetectionViewModel.installationHint(for: "aider"))
        XCTAssertNil(AdapterDetectionViewModel.installationHint(for: "unknown-vendor"))
    }

    func testSortedAdapterIDsIsAlphabetical() async throws {
        let registry = AdapterRegistry()
        try await registry.register(
            FakeAdapter(id: "zeta", isInstalled: true, version: nil)
        )
        try await registry.register(
            FakeAdapter(id: "alpha", isInstalled: true, version: nil)
        )
        try await registry.register(
            FakeAdapter(id: "mike", isInstalled: true, version: nil)
        )
        let viewModel = AdapterDetectionViewModel(registry: registry)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.sortedAdapterIDs, ["alpha", "mike", "zeta"])
    }
}

private struct FakeAdapter: AgentAdapter {
    let adapterID: String
    let installed: Bool
    let versionString: String?

    init(id: String, isInstalled: Bool, version: String?) {
        self.adapterID = id
        self.installed = isInstalled
        self.versionString = version
    }

    static var id: String { "" }
    static var displayName: String { "Fake" }
    var id: String { adapterID }
    var displayName: String { "Fake \(adapterID)" }
    var iconName: String { "terminal" }

    func detect() async -> AdapterDetection {
        AdapterDetection(
            isInstalled: installed,
            version: versionString,
            executablePath: installed ? URL(fileURLWithPath: "/usr/bin/\(adapterID)") : nil,
            detectedAt: Date()
        )
    }

    func createSession(folderPath: URL) async throws -> Session {
        throw AdapterError.unsupported(operation: "fake")
    }

    func destroySession(_ id: SessionID) async throws {}

    func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        throw AdapterError.unsupported(operation: "fake")
    }
}
