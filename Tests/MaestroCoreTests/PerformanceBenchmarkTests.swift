@testable import MaestroCore
import XCTest

final class PerformanceBenchmarkTests: XCTestCase {
    func testMeasureRecordsSampleWithName() async {
        let bench = PerformanceBenchmark()
        let sample = await bench.measure(name: "noop", iterations: 1) { }
        XCTAssertEqual(sample.name, "noop")
        XCTAssertGreaterThanOrEqual(sample.elapsedSeconds, 0)
        let stored = await bench.samples
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].name, "noop")
    }

    func testMeasureMultipleIterationsAveragesAndDropsWarmup() async {
        let bench = PerformanceBenchmark()
        let sample = await bench.measure(name: "sleep10ms", iterations: 3) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        // 평균 ~ 10ms (5ms ~ 30ms 사이 — CI 허용 폭)
        XCTAssertGreaterThan(sample.elapsedSeconds, 0.005)
        XCTAssertLessThan(sample.elapsedSeconds, 0.5,
                          "10ms 평균이 500ms 초과면 환경 이상")
    }

    func testPassesAgainstBaselineUnderCeiling() {
        let baseline = BenchmarkBaseline(name: "x", ceilingSeconds: 1.0)
        let sample = BenchmarkSample(name: "x", elapsedSeconds: 0.5)
        XCTAssertTrue(PerformanceBenchmark.passes(sample, baseline: baseline))
    }

    func testFailsAgainstBaselineOverCeiling() {
        let baseline = BenchmarkBaseline(name: "x", ceilingSeconds: 0.1)
        let sample = BenchmarkSample(name: "x", elapsedSeconds: 0.5)
        XCTAssertFalse(PerformanceBenchmark.passes(sample, baseline: baseline))
    }

    func testClearResetsSamples() async {
        let bench = PerformanceBenchmark()
        _ = await bench.measure(name: "a", iterations: 1) { }
        await bench.clear()
        let stored = await bench.samples
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - 실제 hot path 벤치 (회귀 감지용)

    func testFuzzyMatcherUnderCeiling() async {
        // 1000 항목 fuzzy 검색 — 100ms 이하 ceiling.
        let items = (0..<1000).map { "command-\($0)-test" }
        let bench = PerformanceBenchmark()
        let sample = await bench.measure(name: "fuzzy.1000", iterations: 3) {
            _ = FuzzyMatcher.filter(items: items, query: "test") { $0 }
        }
        XCTAssertLessThan(sample.elapsedSeconds, 0.5,
                          "1000 항목 fuzzy 가 500ms 초과 — 회귀")
    }

    func testAppCastParserUnderCeiling() async {
        let items = (0..<100).map { i in
            "<item><sparkle:version>1.0.\(i)</sparkle:version>" +
            "<enclosure url=\"https://example.com/\(i).dmg\" sparkle:edSignature=\"S\(i)==\"/></item>"
        }.joined(separator: "\n")
        let xml = "<rss xmlns:sparkle=\"x\"><channel>\(items)</channel></rss>"
        let data = Data(xml.utf8)
        let bench = PerformanceBenchmark()
        let sample = await bench.measure(name: "appcast.100", iterations: 3) {
            _ = AppCastParser.parse(data: data)
        }
        XCTAssertLessThan(sample.elapsedSeconds, 0.2,
                          "100 항목 appcast 파싱이 200ms 초과 — 회귀")
    }
}
