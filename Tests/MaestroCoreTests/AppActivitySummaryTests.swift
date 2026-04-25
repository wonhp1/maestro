@testable import MaestroCore
import XCTest

@MainActor
final class AppActivitySummaryTests: XCTestCase {
    func testZeroStateHasNoBadgeAndNoActivity() {
        let summary = AppActivitySummary()
        XCTAssertNil(summary.dockBadgeLabel)
        XCTAssertFalse(summary.hasAnyActivity)
        XCTAssertEqual(summary.menuBarSummaryLine, "에이전트 0")
    }

    func testRunningPlusUnreadProducesBadge() {
        let summary = AppActivitySummary()
        summary.runningDispatchCount = 2
        summary.unreadInboxCount = 3
        XCTAssertEqual(summary.dockBadgeLabel, "5")
        XCTAssertTrue(summary.hasAnyActivity)
    }

    func testMenuBarLineIncludesActiveSegments() {
        let summary = AppActivitySummary()
        summary.folderCount = 4
        summary.runningDispatchCount = 1
        summary.unreadInboxCount = 0
        XCTAssertEqual(summary.menuBarSummaryLine, "에이전트 4 · 진행 1")

        summary.runningDispatchCount = 0
        summary.unreadInboxCount = 2
        XCTAssertEqual(summary.menuBarSummaryLine, "에이전트 4 · 미확인 2")

        summary.unreadInboxCount = 0
        XCTAssertEqual(summary.menuBarSummaryLine, "에이전트 4")
    }

    func testRunningOnlyTriggersBadge() {
        let summary = AppActivitySummary()
        summary.runningDispatchCount = 1
        XCTAssertEqual(summary.dockBadgeLabel, "1")
    }

    func testUnreadOnlyTriggersBadge() {
        let summary = AppActivitySummary()
        summary.unreadInboxCount = 4
        XCTAssertEqual(summary.dockBadgeLabel, "4")
    }
}
