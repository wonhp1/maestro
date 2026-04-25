import Foundation

/// 성능 측정 결과 단일 sample.
public struct BenchmarkSample: Sendable, Equatable, Codable {
    public let name: String
    public let elapsedSeconds: Double
    public let measuredAt: Date

    public init(name: String, elapsedSeconds: Double, measuredAt: Date = Date()) {
        self.name = name
        self.elapsedSeconds = elapsedSeconds
        self.measuredAt = measuredAt
    }
}

/// 베이스라인 (목표/임계값) — 측정값과 비교하여 회귀 감지.
public struct BenchmarkBaseline: Sendable, Codable, Equatable {
    public let name: String
    /// 평균 임계 (s) — 이 값보다 크면 회귀 의심.
    public let ceilingSeconds: Double
    /// 측정 회수 (default 5).
    public let iterations: Int

    public init(name: String, ceilingSeconds: Double, iterations: Int = 5) {
        self.name = name
        self.ceilingSeconds = max(0, ceilingSeconds)
        self.iterations = max(1, iterations)
    }
}

/// 동기/비동기 closure 의 wall-clock 측정 utility.
///
/// ## 사용
/// ```swift
/// let bench = PerformanceBenchmark()
/// let sample = await bench.measure(name: "fuzzy.1000", iterations: 5) {
///     _ = FuzzyMatcher.filter(items: items, query: "abc") { $0 }
/// }
/// XCTAssertLessThan(sample.elapsedSeconds, 0.1)
/// ```
///
/// ## 결정성
/// `iterations` 회 평균. 첫 회 (warmup) 는 결과에서 제외. `iterations < 2` 이면
/// warmup 없이 그대로.
public actor PerformanceBenchmark {
    public private(set) var samples: [BenchmarkSample] = []

    public init() {}

    public func measure(
        name: String,
        iterations: Int = 5,
        _ block: @Sendable () async -> Void
    ) async -> BenchmarkSample {
        let count = max(1, iterations)
        // warmup
        if count >= 2 { await block() }
        let measuredCount = count >= 2 ? count : count
        var total: Double = 0
        for _ in 0..<measuredCount {
            let start = ContinuousClock.now
            await block()
            let dur = ContinuousClock.now - start
            total += Self.seconds(of: dur)
        }
        let avg = total / Double(measuredCount)
        let sample = BenchmarkSample(name: name, elapsedSeconds: avg)
        samples.append(sample)
        return sample
    }

    public func clear() {
        samples.removeAll()
    }

    /// 베이스라인과 비교 — 임계 초과 시 false.
    public static func passes(_ sample: BenchmarkSample, baseline: BenchmarkBaseline) -> Bool {
        sample.elapsedSeconds <= baseline.ceilingSeconds
    }

    private static func seconds(of duration: ContinuousClock.Duration) -> Double {
        let comps = duration.components
        return Double(comps.seconds) + Double(comps.attoseconds) / 1e18
    }
}
