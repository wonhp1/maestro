@testable import MaestroCore
import XCTest

final class FuzzyMatcherTests: XCTestCase {
    func testEmptyQueryReturnsZeroScore() {
        XCTAssertEqual(FuzzyMatcher.score(query: "", in: "anything"), 0)
    }

    func testQueryLongerThanTitleReturnsNil() {
        XCTAssertNil(FuzzyMatcher.score(query: "abcdef", in: "ab"))
    }

    func testExactMatchScoresHigh() {
        let score = FuzzyMatcher.score(query: "open", in: "open")
        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score!, 10)
    }

    func testSubsequenceMatchSucceeds() {
        let score = FuzzyMatcher.score(query: "fld", in: "folder")
        XCTAssertNotNil(score)
    }

    func testNonSubsequenceReturnsNil() {
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", in: "folder"))
    }

    func testCaseInsensitive() {
        let lower = FuzzyMatcher.score(query: "fold", in: "folder")
        let upper = FuzzyMatcher.score(query: "FOLD", in: "Folder")
        XCTAssertEqual(lower, upper)
    }

    func testConsecutiveCharsScoreHigherThanScattered() {
        let consecutive = FuzzyMatcher.score(query: "open", in: "open file")
        let scattered = FuzzyMatcher.score(query: "open", in: "o p e n file")
        XCTAssertNotNil(consecutive)
        XCTAssertNotNil(scattered)
        XCTAssertGreaterThan(consecutive!, scattered!)
    }

    func testWordBoundaryBonus() {
        // "f" 가 단어 시작 — bonus
        let atBoundary = FuzzyMatcher.score(query: "f", in: "open folder")
        let noBoundary = FuzzyMatcher.score(query: "f", in: "ofiel")
        XCTAssertNotNil(atBoundary)
        XCTAssertNotNil(noBoundary)
        XCTAssertGreaterThan(atBoundary!, noBoundary!)
    }

    func testFilterReturnsMatchingItemsWithScores() {
        let items = ["folder switch", "discussion", "settings", "folder add"]
        let results = FuzzyMatcher.filter(items: items, query: "fold") { $0 }
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.item.contains("folder") })
    }

    func testKoreanQuery() {
        let score = FuzzyMatcher.score(query: "폴더", in: "폴더 전환")
        XCTAssertNotNil(score)
    }
}
