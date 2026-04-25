import Foundation

/// 시스템에서 특정 CLI 어댑터의 **현재 설치 상태** 스냅샷.
///
/// `AgentAdapter.detect()` 가 반환. `AdapterRegistry` 또는 UI 가 캐시하여
/// 사용자에게 어떤 에이전트가 사용 가능한지 표시.
///
/// - `isInstalled` 가 `false` 일 때 `version`/`executablePath` 는 항상 `nil`.
/// - `version` 은 어댑터별 정규식으로 추출됨. 추출 실패 시 `nil` 가능 (설치는 됨).
/// - `detectedAt` 으로 캐시 신선도 판단 (수동 재감지 트리거).
public struct AdapterDetection: Codable, Hashable, Sendable {
    public let isInstalled: Bool
    public let version: String?
    public let executablePath: URL?
    public let detectedAt: Date

    public init(
        isInstalled: Bool,
        version: String?,
        executablePath: URL?,
        detectedAt: Date
    ) {
        self.isInstalled = isInstalled
        self.version = version
        self.executablePath = executablePath
        self.detectedAt = detectedAt
    }

    /// "설치되지 않음" 결과 — 편의 팩토리.
    public static func notInstalled(at time: Date = Date()) -> AdapterDetection {
        AdapterDetection(
            isInstalled: false,
            version: nil,
            executablePath: nil,
            detectedAt: time
        )
    }
}
