import Foundation

/// Maestro 앱의 정적 메타데이터와 기본 설정값.
///
/// 하드코딩된 값들은 여기 한 곳에서 관리하여 테스트와 설정 화면에서 참조.
public enum MaestroConfig {
    public static let appName: String = "Maestro"
    public static let bundleIdentifier: String = "com.gimgyeongwon.maestro"
    public static let appVersion: String = "0.1.0"

    /// 최소 지원 macOS 버전. Package.swift `platforms` 와 반드시 일치 유지.
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
