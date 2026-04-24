import XCTest
@testable import MaestroCore

/// Phase 1 / Test 1.1 — 앱 시작 시 필요한 핵심 상수와 메타데이터가 정의되어 있는지 확인한다.
///
/// SwiftUI `@main` struct 자체는 테스트 불가능 (UI 테스트 영역).
/// 대신 `MaestroConfig` 에 노출된 상수를 통해 앱 부트스트랩의 계약을 검증한다.
final class AppLaunchTests: XCTestCase {
    func testAppNameIsMaestro() {
        XCTAssertEqual(MaestroConfig.appName, "Maestro")
    }

    func testAppBundleIdentifierFormat() {
        let bundleID = MaestroConfig.bundleIdentifier
        XCTAssertTrue(bundleID.hasPrefix("com."), "번들 ID는 reverse-DNS 형식이어야 함")
        XCTAssertTrue(bundleID.contains("maestro"), "번들 ID에 'maestro' 포함되어야 함")
    }

    func testAppVersionIsSemver() {
        let version = MaestroConfig.appVersion
        let parts = version.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "버전은 major.minor.patch 형식 (\(version))")
        for part in parts {
            XCTAssertNotNil(Int(part), "버전 구성요소는 숫자여야 함 (\(part))")
        }
    }

    func testMinimumMacOSVersionIsSpecified() {
        // macOS 14+ 요구 — 명시적 상수로 방어
        XCTAssertGreaterThanOrEqual(MaestroConfig.minimumMacOSVersion.major, 14)
    }
}
