@testable import MaestroCore
import XCTest

final class AppVersionTests: XCTestCase {
    func testParseFullSemver() {
        let v = AppVersion(string: "1.2.3")
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
        XCTAssertNil(v?.preRelease)
    }

    func testParseShortVersions() {
        XCTAssertEqual(AppVersion(string: "1"), AppVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(AppVersion(string: "1.5"), AppVersion(major: 1, minor: 5, patch: 0))
    }

    func testParsePreRelease() {
        let v = AppVersion(string: "0.2.0-beta.3")
        XCTAssertEqual(v?.preRelease, "beta.3")
    }

    func testParseStripsLeadingV() {
        XCTAssertEqual(AppVersion(string: "v2.0.0"), AppVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(AppVersion(string: "V3.1.4"), AppVersion(major: 3, minor: 1, patch: 4))
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(AppVersion(string: ""))
        XCTAssertNil(AppVersion(string: "abc"))
        XCTAssertNil(AppVersion(string: "1.2.3.4"))
        XCTAssertNil(AppVersion(string: "1.x.0"))
    }

    func testComparesByCorePartsFirst() {
        XCTAssertLessThan(AppVersion(major: 1, minor: 0, patch: 0),
                          AppVersion(major: 2, minor: 0, patch: 0))
        XCTAssertLessThan(AppVersion(major: 1, minor: 1, patch: 0),
                          AppVersion(major: 1, minor: 2, patch: 0))
        XCTAssertLessThan(AppVersion(major: 1, minor: 0, patch: 1),
                          AppVersion(major: 1, minor: 0, patch: 2))
    }

    func testPreReleaseIsLessThanStable() {
        let beta = AppVersion(major: 1, minor: 0, patch: 0, preRelease: "beta.1")
        let stable = AppVersion(major: 1, minor: 0, patch: 0)
        XCTAssertLessThan(beta, stable)
    }

    func testDescriptionRoundtrips() {
        XCTAssertEqual(AppVersion(major: 1, minor: 2, patch: 3).description, "1.2.3")
        XCTAssertEqual(
            AppVersion(major: 1, minor: 0, patch: 0, preRelease: "rc.1").description,
            "1.0.0-rc.1"
        )
    }
}
