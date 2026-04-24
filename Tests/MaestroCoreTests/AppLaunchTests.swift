@testable import MaestroCore
import XCTest

/// Phase 1 / Test 1.1 — 앱 시작 시 필요한 핵심 상수와 메타데이터가 정의되어 있는지 확인한다.
///
/// SwiftUI `@main` struct 자체는 테스트 불가능 (UI 테스트 영역).
/// 대신 `MaestroConfig` 에 노출된 상수를 통해 앱 부트스트랩의 계약을 검증한다.
final class AppLaunchTests: XCTestCase {
    func testAppNameIsMaestro() {
        XCTAssertEqual(MaestroConfig.appName, "Maestro")
    }

    func testAppBundleIdentifierPinnedValue() {
        // Pin to exact value — 코드 서명 / Sparkle / 노타리제이션 연동점
        XCTAssertEqual(MaestroConfig.bundleIdentifier, "com.gimgyeongwon.maestro")
    }

    func testAppVersionIsSemverAndNonZero() {
        let version = MaestroConfig.appVersion
        let parts = version.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "버전은 major.minor.patch 형식 (\(version))")
        for part in parts {
            XCTAssertNotNil(Int(part), "버전 구성요소는 숫자여야 함 (\(part))")
        }
        // 우연한 리셋 방지
        XCTAssertNotEqual(version, "0.0.0", "빈 버전 문자열 방지")
    }

    func testMinimumMacOSVersionIsSpecified() {
        // macOS 14+ 요구 — 명시적 상수로 방어
        XCTAssertGreaterThanOrEqual(MaestroConfig.minimumMacOSVersion.major, 14)
    }

    /// Package.swift `.macOS(.v14)` 와 `MaestroConfig.minimumMacOSVersion` 는 반드시 같아야 한다.
    /// Package.swift 를 런타임에 파싱하지 않고, 두 곳을 함께 바꾸는 것을 테스트가 강제.
    func testMacOSVersionInvariantMatchesPackageDeclaration() {
        XCTAssertEqual(MaestroConfig.minimumMacOSVersion.major, 14)
        XCTAssertEqual(MaestroConfig.minimumMacOSVersion.minor, 0)
    }
}
