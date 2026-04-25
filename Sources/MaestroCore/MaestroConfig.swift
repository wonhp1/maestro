// 표준 라이브러리만 사용 — Foundation 불필요.

/// Maestro 앱의 정적 메타데이터와 기본 설정값.
///
/// 하드코딩된 값들은 여기 한 곳에서 관리하여 테스트와 설정 화면에서 참조.
///
/// - Important: 이 enum 은 **빌드 타임 상수 전용**. 사용자 변경 가능한 설정은
///   향후 별도의 `AppSettings` observable 타입에서 관리 (Phase 19 설정 UI 참조).
public enum MaestroConfig {
    /// 앱 표시 이름.
    public static let appName: String = "Maestro"

    /// 번들 ID (reverse-DNS). 코드 서명 / Sparkle / Keychain 서비스 식별자의 기준.
    ///
    /// - Note: SwiftPM executable 빌드에서는 무시되지만, Xcode 프로젝트 래핑 (Phase 21)
    ///   시 Info.plist `CFBundleIdentifier` 와 일치해야 함.
    public static let bundleIdentifier: String = "com.gimgyeongwon.maestro"

    /// 현재 앱 버전 (SemVer).
    ///
    /// - Warning: Phase 21 Sparkle 통합 시 Info.plist `CFBundleShortVersionString` 및
    ///   appcast.xml 과 반드시 동기화. **단일 진실 원천을 유지하려면 Phase 21 에서
    ///   빌드 스크립트로 생성하거나 Info.plist 에서 읽어오도록 리팩터링 예정.**
    public static let appVersion: String = "0.4.3"

    /// 최소 지원 macOS 버전.
    ///
    /// - Important: **SEE ALSO** `Package.swift` `platforms: [.macOS(.v14)]`. 두 값은
    ///   반드시 일치. `AppLaunchTests.testMacOSVersionInvariantMatchesPackageDeclaration`
    ///   가 드리프트를 감지.
    public static let minimumMacOSVersion: MacOSVersion = MacOSVersion(major: 14, minor: 0)

    /// 윈도우 최소 크기 — 컨트롤 타워 3-컬럼 레이아웃 하한.
    public static let minimumWindowSize: WindowSize = WindowSize(width: 1000, height: 700)

    /// 윈도우 기본 크기 — 첫 실행 시 적용.
    public static let defaultWindowSize: WindowSize = WindowSize(width: 1280, height: 800)

    /// 윈도우 타이틀의 로컬라이즈 키. 실제 문자열은 Phase 22에서 String Catalog로 이동.
    public static let defaultWindowTitleKey: String = "window.main.title"
}

public struct MacOSVersion: Sendable, Equatable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }
}

public struct WindowSize: Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
