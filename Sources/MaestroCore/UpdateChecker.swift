import Foundation

/// `URLSession` 추상 — 테스트가 stub 으로 교체.
public protocol AppCastFetching: Sendable {
    func fetch(_ url: URL) async throws -> Data
}

public struct URLSessionAppCastFetcher: AppCastFetching {
    public let session: URLSession
    public let timeoutSeconds: TimeInterval

    public init(
        session: URLSession = .shared,
        timeoutSeconds: TimeInterval = 15
    ) {
        self.session = session
        self.timeoutSeconds = timeoutSeconds
    }

    public func fetch(_ url: URL) async throws -> Data {
        guard url.scheme == "https" else {
            throw UpdateCheckerError.insecureURL(url)
        }
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateCheckerError.httpStatus(http.statusCode)
        }
        if data.count > 1 * 1024 * 1024 {
            throw UpdateCheckerError.responseTooLarge(bytes: data.count)
        }
        return data
    }
}

public enum UpdateCheckerError: Error, Equatable, Sendable {
    case insecureURL(URL)
    case httpStatus(Int)
    case responseTooLarge(bytes: Int)
    case malformedAppCast
}

/// 자동 업데이트 검사 — appcast XML 다운로드 + 현재 버전 보다 큰 첫 항목 반환.
///
/// ## 보안
/// - **HTTPS 강제** (fetcher 가 검증).
/// - **응답 크기 cap** 1 MiB.
/// - 다운로드 자체는 별도 — 본 액터는 메타데이터 확인만.
/// - **EdDSA 서명 검증** 은 Sparkle 본체 책임 — 본 액터는 서명 존재 여부만 확인.
public actor UpdateChecker {
    public let appCastURL: URL
    public let currentVersion: AppVersion
    public let fetcher: AppCastFetching
    public let requireSignature: Bool

    public private(set) var lastCheckedAt: Date?
    public private(set) var lastResult: Result?

    public init(
        appCastURL: URL,
        currentVersion: AppVersion,
        fetcher: AppCastFetching,
        requireSignature: Bool = true
    ) {
        self.appCastURL = appCastURL
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.requireSignature = requireSignature
    }

    public enum Result: Sendable, Equatable {
        case upToDate
        case available(AppCastItem)
        case unsignedAvailable(AppCastItem)
    }

    @discardableResult
    public func check(now: Date = Date()) async throws -> Result {
        let data = try await fetcher.fetch(appCastURL)
        let items = AppCastParser.parse(data: data)
        if items.isEmpty {
            throw UpdateCheckerError.malformedAppCast
        }
        let newer = items
            .filter { $0.version > currentVersion }
            .sorted { $0.version > $1.version }
        let result: Result
        if let candidate = newer.first {
            if requireSignature && (candidate.edSignature ?? "").isEmpty {
                result = .unsignedAvailable(candidate)
            } else {
                result = .available(candidate)
            }
        } else {
            result = .upToDate
        }
        lastResult = result
        lastCheckedAt = now
        return result
    }
}
