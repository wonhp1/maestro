import Foundation

/// 사용자 설정의 디스크 스키마. 단일 JSON 파일 (`AppSupport/preferences.json`).
///
/// 추가 필드는 모두 옵셔널 + 기본값 — 구버전 파일 로드 시 graceful migration.
public struct PreferencesSnapshot: Codable, Equatable, Sendable {
    public var firstRunCompleted: Bool
    public var notificationsEnabled: Bool
    public var launchAtLogin: Bool
    public var enabledAdapterIDs: Set<String>
    public var preferredAdapterID: String?
    public var dispatchTimeoutSeconds: Int

    public init(
        firstRunCompleted: Bool = false,
        notificationsEnabled: Bool = true,
        launchAtLogin: Bool = false,
        enabledAdapterIDs: Set<String> = ["claude"],
        preferredAdapterID: String? = "claude",
        dispatchTimeoutSeconds: Int = 120
    ) {
        self.firstRunCompleted = firstRunCompleted
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
        self.enabledAdapterIDs = enabledAdapterIDs
        self.preferredAdapterID = preferredAdapterID
        self.dispatchTimeoutSeconds = max(5, min(dispatchTimeoutSeconds, 3600))
    }

    public static let `default` = PreferencesSnapshot()
}
