import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// 실제 `aider` CLI 가 PATH 에 있을 때만 실행되는 통합 테스트.
/// CI / dev 환경에 미설치 시 모든 테스트 스킵.
final class AiderAdapterIntegrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try requireAider()
        tempDir = try TestSupport.makeTempDirectory(named: "aider-int")
    }

    override func tearDown() {
        if let tempDir { TestSupport.removeTempDirectory(tempDir) }
        super.tearDown()
    }

    private func requireAider() throws {
        let locator = PATHExecutableLocator()
        guard locator.locate("aider") != nil else {
            throw XCTSkip("aider CLI not in PATH — integration test skipped")
        }
    }

    func testDetectFindsRealAiderCLI() async throws {
        let adapter = try AiderAdapter()
        let detection = await adapter.detect()
        XCTAssertTrue(detection.isInstalled)
        XCTAssertNotNil(detection.version)
        XCTAssertNotNil(detection.executablePath)
    }

    func testStaticMetadataMatchesProfile() {
        XCTAssertEqual(AiderAdapter.id, AiderProfile.adapterID)
        XCTAssertEqual(AiderAdapter.displayName, AiderProfile.displayName)
    }

    func testCreateAndDestroyRealSession() async throws {
        let adapter = try AiderAdapter(chatHistoryRoot: tempDir)
        let session = try await adapter.createSession(folderPath: tempDir)
        XCTAssertEqual(session.adapterId.rawValue, "aider")
        let historyPath = await adapter.chatHistoryPath(for: session.id)
        XCTAssertNotNil(historyPath)
        try await adapter.destroySession(session.id)
        let active = await adapter.activeSessionIds()
        XCTAssertTrue(active.isEmpty)
    }
}
