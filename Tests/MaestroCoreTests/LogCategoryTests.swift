@testable import MaestroCore
import XCTest

final class LogCategoryTests: XCTestCase {
    func testAllCasesAreStableStrings() {
        // 카테고리 raw 가 바뀌면 Console.app 필터가 깨짐 — 의도적 변경 아니면 테스트로 차단.
        let expected: [LogCategory: String] = [
            .adapter: "adapter",
            .persistence: "persistence",
            .routing: "routing",
            .dispatch: "dispatch",
            .orchestration: "orchestration",
            .process: "process",
            .network: "network",
            .security: "security",
            .ui: "ui",
            .general: "general",
        ]
        for (kase, raw) in expected {
            XCTAssertEqual(kase.rawValue, raw)
        }
        XCTAssertEqual(Set(LogCategory.allCases), Set(expected.keys))
    }

    func testRawValueLookup() {
        for kase in LogCategory.allCases {
            XCTAssertEqual(LogCategory(rawValue: kase.rawValue), kase)
        }
    }
}
