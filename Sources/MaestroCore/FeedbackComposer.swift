import Foundation

/// 사용자가 GitHub Issues / 피드백 폼에 붙여넣을 수 있도록 시스템 + 앱 정보를
/// 모은 텍스트 페이로드.
///
/// **로컬 앱은 외부 서버로 자동 전송 X** — 사용자가 명시적으로 복사 → 외부 폼에 붙여넣기.
/// 시크릿 / API 키 / 사용자 메시지 본문은 절대 포함 X.
public struct FeedbackPayload: Sendable, Equatable, Codable {
    public let appName: String
    public let appVersion: String
    public let bundleIdentifier: String
    public let macOSVersionString: String
    public let detectedCLIs: [String]
    public let createdAt: Date
    public let userNote: String

    public init(
        appName: String,
        appVersion: String,
        bundleIdentifier: String,
        macOSVersionString: String,
        detectedCLIs: [String],
        userNote: String,
        createdAt: Date = Date()
    ) {
        self.appName = appName
        self.appVersion = appVersion
        self.bundleIdentifier = bundleIdentifier
        self.macOSVersionString = macOSVersionString
        self.detectedCLIs = detectedCLIs
        self.userNote = userNote
        self.createdAt = createdAt
    }

    /// GitHub Issues / 메일 본문에 그대로 붙여넣기 좋은 형식.
    public func renderMarkdown() -> String {
        let cliList = detectedCLIs.isEmpty ? "(none)" : detectedCLIs.joined(separator: ", ")
        let safeNote = DisplayTextSanitizer.sanitize(userNote)
        return """
        ## Maestro Feedback

        - **App**: \(appName) \(appVersion) (\(bundleIdentifier))
        - **macOS**: \(macOSVersionString)
        - **Detected CLIs**: \(cliList)
        - **Created**: \(createdAt.ISO8601Format())

        ### User note

        \(safeNote.isEmpty ? "_(empty)_" : safeNote)
        """
    }
}

/// 시스템 정보 수집 + payload 빌더 — 외부 호출자가 user note + detected CLIs 만 추가.
public enum FeedbackComposer {
    public static func compose(
        userNote: String,
        detectedCLIs: [String],
        appName: String = MaestroConfig.appName,
        appVersion: String = MaestroConfig.appVersion,
        bundleIdentifier: String = MaestroConfig.bundleIdentifier,
        macOSVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        now: Date = Date()
    ) -> FeedbackPayload {
        let macOSString = "\(macOSVersion.majorVersion).\(macOSVersion.minorVersion).\(macOSVersion.patchVersion)"
        return FeedbackPayload(
            appName: appName,
            appVersion: appVersion,
            bundleIdentifier: bundleIdentifier,
            macOSVersionString: macOSString,
            detectedCLIs: detectedCLIs,
            userNote: userNote,
            createdAt: now
        )
    }
}
