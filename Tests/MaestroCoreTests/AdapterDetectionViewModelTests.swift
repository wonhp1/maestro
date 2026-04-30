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
        // v0.9.0
        XCTAssertNotNil(AdapterDetectionViewModel.installationHint(for: "codex"))
        XCTAssertNotNil(AdapterDetectionViewModel.installationHint(for: "gemini"))
        XCTAssertNil(AdapterDetectionViewModel.installationHint(for: "unknown-vendor"))
    }

    func testCodexInstallationHintHasCorrectCommand() {
        let hint = AdapterDetectionViewModel.installationHint(for: "codex")
        XCTAssertEqual(hint?.command, "npm install -g @openai/codex")
        XCTAssertNotNil(hint?.docsURL)
    }

    func testGeminiInstallationHintHasCorrectCommand() {
        let hint = AdapterDetectionViewModel.installationHint(for: "gemini")
        XCTAssertEqual(hint?.command, "npm install -g @google/gemini-cli")
        XCTAssertNotNil(hint?.docsURL)
    }

    func testDescriptionsForKnownAdapters() {
        XCTAssertNotNil(AdapterDetectionViewModel.description(for: "claude"))
        XCTAssertNotNil(AdapterDetectionViewModel.description(for: "aider"))
        XCTAssertNotNil(AdapterDetectionViewModel.description(for: "codex"))
        XCTAssertNotNil(AdapterDetectionViewModel.description(for: "gemini"))
    }

    func testGeminiHasFreeBadge() {
        XCTAssertEqual(
            AdapterDetectionViewModel.recommendationBadge(for: "gemini"),
            "무료 tier 있음"
        )
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
