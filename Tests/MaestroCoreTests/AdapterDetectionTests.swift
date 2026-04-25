@testable import MaestroCore
import XCTest

final class AdapterDetectionTests: XCTestCase {
    func testNotInstalledFactoryProducesEmptyVersionAndPath() {
        let now = Date(timeIntervalSince1970: 1_714_500_000)
        let detection = AdapterDetection.notInstalled(at: now)
        XCTAssertFalse(detection.isInstalled)
        XCTAssertNil(detection.version)
        XCTAssertNil(detection.executablePath)
        XCTAssertEqual(detection.detectedAt, now)
    }

    func testCodableRoundtripPreservesAllFields() throws {
        let original = AdapterDetection(
            isInstalled: true,
            version: "1.2.3",
            executablePath: URL(fileURLWithPath: "/usr/local/bin/claude"),
            detectedAt: Date(timeIntervalSince1970: 1_714_500_000)
        )
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(AdapterDetection.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEqualityComparesAllFields() {
        let a = AdapterDetection(
            isInstalled: true, version: "1", executablePath: nil,
            detectedAt: Date(timeIntervalSince1970: 0)
        )
        let b = AdapterDetection(
            isInstalled: true, version: "1", executablePath: nil,
            detectedAt: Date(timeIntervalSince1970: 0)
        )
        let c = AdapterDetection(
            isInstalled: true, version: "2", executablePath: nil,
            detectedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
