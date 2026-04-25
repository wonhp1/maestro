import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// 실제 `claude` CLI 가 PATH 에 있을 때만 실행되는 통합 테스트.
/// CI 등 미설치 환경에서는 모든 테스트 스킵 (XCTSkip).
final class ClaudeAdapterIntegrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try requireClaude()
        tempDir = try TestSupport.makeTempDirectory(named: "claude-int")
    }

    override func tearDown() {
        if let tempDir { TestSupport.removeTempDirectory(tempDir) }
        super.tearDown()
    }

    private func requireClaude() throws {
        let locator = PATHExecutableLocator()
        guard locator.locate("claude") != nil else {
            throw XCTSkip("claude CLI not in PATH — integration test skipped")
        }
    }

    func testDetectFindsRealClaudeCLI() async throws {
        let adapter = try ClaudeAdapter()
        let detection = await adapter.detect()
        XCTAssertTrue(detection.isInstalled, "claude not detected")
        XCTAssertNotNil(detection.version, "version not extracted")
        XCTAssertNotNil(detection.executablePath)
    }

    func testStaticMetadataMatchesProfile() {
        XCTAssertEqual(ClaudeAdapter.id, ClaudeProfile.adapterID)
        XCTAssertEqual(ClaudeAdapter.displayName, ClaudeProfile.displayName)
    }

    func testCreateAndDestroyRealSession() async throws {
        let adapter = try ClaudeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        XCTAssertEqual(session.adapterId.rawValue, "claude")
        try await adapter.destroySession(session.id)
        let active = await adapter.activeSessionIds()
        XCTAssertTrue(active.isEmpty)
    }
}
