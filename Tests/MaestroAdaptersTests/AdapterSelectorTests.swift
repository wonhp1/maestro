@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class AdapterSelectorTests: XCTestCase {
    private actor StubAdapter: AgentAdapter {
        nonisolated static let id: String = "_unused"
        nonisolated static let displayName: String = "Stub"
        nonisolated static let iconName: String = ""
        nonisolated let id: String
        nonisolated let displayName: String
        nonisolated let iconName: String
        let installed: Bool

        init(id: String, installed: Bool) {
            self.id = id
            self.displayName = id
            self.iconName = ""
            self.installed = installed
        }

        func detect() async -> AdapterDetection {
            installed
                ? AdapterDetection(
                    isInstalled: true,
                    version: "1.0",
                    executablePath: URL(fileURLWithPath: "/usr/bin/\(id)"),
                    detectedAt: Date()
                )
                : AdapterDetection.notInstalled()
        }

        func createSession(folderPath: URL) async throws -> Session {
            throw NSError(domain: "stub", code: 0)
        }
        func destroySession(_ id: SessionID) async throws {}
        func sendMessage(_ envelope: MessageEnvelope, in session: Session) async throws -> MessageEnvelope {
            envelope
        }
        func listSlashCommands(in session: Session) async -> [SlashCommand] { [] }
    }

    func testPreferredAdapterUsedWhenDetectedAndEnabled() async {
        let claude = StubAdapter(id: "claude", installed: true)
        let aider = StubAdapter(id: "aider", installed: true)
        let mock = StubAdapter(id: "mock", installed: true)
        let selector = AdapterSelector(
            candidates: ["claude": claude, "aider": aider],
            fallback: mock
        )
        let result = await selector.select(preferred: "aider", enabled: ["claude", "aider"])
        XCTAssertEqual(result.id, "aider")
    }

    func testPreferredSkippedWhenNotInstalledFallsToFirstEnabled() async {
        let claude = StubAdapter(id: "claude", installed: true)
        let aider = StubAdapter(id: "aider", installed: false)
        let mock = StubAdapter(id: "mock", installed: true)
        let selector = AdapterSelector(
            candidates: ["claude": claude, "aider": aider],
            fallback: mock
        )
        let result = await selector.select(preferred: "aider", enabled: ["claude", "aider"])
        XCTAssertEqual(result.id, "claude")
    }

    func testFallbackWhenNoneInstalled() async {
        let claude = StubAdapter(id: "claude", installed: false)
        let aider = StubAdapter(id: "aider", installed: false)
        let mock = StubAdapter(id: "mock", installed: true)
        let selector = AdapterSelector(
            candidates: ["claude": claude, "aider": aider],
            fallback: mock
        )
        let result = await selector.select(preferred: "claude", enabled: ["claude", "aider"])
        XCTAssertEqual(result.id, "mock")
    }

    func testPreferredNotInEnabledIgnored() async {
        let claude = StubAdapter(id: "claude", installed: true)
        let mock = StubAdapter(id: "mock", installed: true)
        let selector = AdapterSelector(
            candidates: ["claude": claude],
            fallback: mock
        )
        let result = await selector.select(preferred: "aider", enabled: ["claude"])
        XCTAssertEqual(result.id, "claude")
    }

    func testDetectAllReturnsAllCandidates() async {
        let claude = StubAdapter(id: "claude", installed: true)
        let aider = StubAdapter(id: "aider", installed: false)
        let selector = AdapterSelector(
            candidates: ["claude": claude, "aider": aider],
            fallback: StubAdapter(id: "x", installed: true)
        )
        let detections = await selector.detectAll()
        XCTAssertEqual(detections.count, 2)
        XCTAssertTrue(detections["claude"]?.isInstalled == true)
        XCTAssertFalse(detections["aider"]?.isInstalled == true)
    }

    func testInstalledAdapterIDsSorted() async {
        let claude = StubAdapter(id: "claude", installed: true)
        let aider = StubAdapter(id: "aider", installed: true)
        let cursor = StubAdapter(id: "cursor", installed: false)
        let selector = AdapterSelector(
            candidates: ["claude": claude, "aider": aider, "cursor": cursor],
            fallback: StubAdapter(id: "x", installed: true)
        )
        let installed = await selector.installedAdapterIDs()
        XCTAssertEqual(installed, ["aider", "claude"])
    }
}
