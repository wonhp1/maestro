@testable import MaestroCore
import XCTest

final class ControlVendorSelectionTests: XCTestCase {
    /// Control folder is identified by a known constant — used by chatViewModelFactory
    /// to decide whether to use the dynamic-prompt ClaudeAdapter or fall through to
    /// the user-chosen adapter.
    func testControlFolderIDConstantStable() {
        // 절대 변경되지 않음 — 변경 시 사용자 데이터 마이그레이션 필요.
        XCTAssertEqual(
            ControlAgentProvisioner.controlFolderID.rawValue,
            "00000000-0000-0000-0000-000000636c74"
        )
    }

    func testIsControlFolderTrueForControl() {
        XCTAssertTrue(ControlAgentProvisioner.isControlFolder(
            ControlAgentProvisioner.controlFolderID
        ))
    }

    func testIsControlFolderFalseForOther() {
        XCTAssertFalse(ControlAgentProvisioner.isControlFolder(FolderID.new()))
    }
}
