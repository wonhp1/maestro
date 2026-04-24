import XCTest
@testable import MaestroCore

/// Phase 1 / Test 1.2 — 메인 윈도우의 최소 크기와 기본 크기 계약 검증.
final class MainWindowTests: XCTestCase {
    func testMinimumWindowSizeMeetsControlTowerNeeds() {
        // 컨트롤 타워 3-컬럼 레이아웃 최소 요구치 (사이드바 + 메인 + 인스펙터)
        XCTAssertGreaterThanOrEqual(MaestroConfig.minimumWindowSize.width, 900)
        XCTAssertGreaterThanOrEqual(MaestroConfig.minimumWindowSize.height, 600)
    }

    func testDefaultWindowSizeLargerThanMinimum() {
        XCTAssertGreaterThanOrEqual(
            MaestroConfig.defaultWindowSize.width,
            MaestroConfig.minimumWindowSize.width
        )
        XCTAssertGreaterThanOrEqual(
            MaestroConfig.defaultWindowSize.height,
            MaestroConfig.minimumWindowSize.height
        )
    }

    func testWindowTitleIsLocalizable() {
        // Phase 22 i18n 대비 — 하드코딩 금지, StringResource 경유
        XCTAssertFalse(
            MaestroConfig.defaultWindowTitleKey.isEmpty,
            "윈도우 타이틀 로컬라이즈 키는 비어있으면 안 됨"
        )
    }
}
