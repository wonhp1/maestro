import Foundation

/// 크래시 리포트 단일 record. 다음 실행 시 사용자에게 표시.
public struct CrashReport: Sendable, Equatable, Codable {
    public let id: String
    public let occurredAt: Date
    public let appVersion: String
    public let kind: Kind
    public let message: String
    public let stackTrace: [String]

    public enum Kind: String, Sendable, Codable {
        case exception
        case signal
    }

    public init(
        id: String = UUID().uuidString,
        occurredAt: Date,
        appVersion: String,
        kind: Kind,
        message: String,
        stackTrace: [String]
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.appVersion = appVersion
        self.kind = kind
        self.message = message
        self.stackTrace = stackTrace
    }
}

/// 디스크 영속 — 크래시 디렉토리에 단일 JSON 파일.
///
/// ## 동작
/// 1. `install()` — `NSSetUncaughtExceptionHandler` + 주요 signal 핸들러 등록.
///    2차 크래시 방지: 이미 reporting 중인 플래그 체크.
/// 2. 크래시 발생 → handler 가 stack trace + message 를 *atomic* JSON 으로 기록.
/// 3. 다음 실행 시 `loadPendingReports()` 가 디렉토리 스캔 → UI 노출 + 사용자 dismiss
///    시 삭제.
///
/// ## 보안
/// - stack trace 는 binary symbol 만, 사용자 데이터 X.
/// - 별도 외부 전송 X — 사용자가 명시적으로 GitHub Issues 등에 복사.
///
/// ## 한계 (Phase 23 ship)
/// signal handler 안에서 안전한 작업은 매우 제한적 (async-signal-safe). 본 구현은
/// 단순 write(2) 만 — 더 견고한 PLCrashReporter 통합은 Phase 24+ 검토.
public struct CrashReporter: Sendable {
    public let directory: URL
    public let appVersion: String

    public init(
        directory: URL,
        appVersion: String = MaestroConfig.appVersion
    ) {
        self.directory = directory
        self.appVersion = appVersion
    }

    public func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    /// 디스크에 크래시 record 기록. atomic write — 부분 파일 없음.
    @discardableResult
    public func record(_ report: CrashReport) throws -> URL {
        try ensureDirectoryExists()
        let url = directory.appending(
            path: "crash-\(report.id).json", directoryHint: .notDirectory
        )
        let data = try JSONEncoder.maestro.encode(report)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
        return url
    }

    /// 다음 실행 시 호출 — 디렉토리의 모든 크래시 report 로드.
    public func loadPendingReports() throws -> [CrashReport] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var reports: [CrashReport] = []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard url.pathExtension == "json" else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let report = try? JSONDecoder.maestro.decode(CrashReport.self, from: data) else {
                continue
            }
            reports.append(report)
        }
        return reports
    }

    /// 사용자 dismiss — 단일 report 삭제.
    public func dismiss(_ reportID: String) throws {
        let url = directory.appending(
            path: "crash-\(reportID).json", directoryHint: .notDirectory
        )
        try FileManager.default.removeItem(at: url)
    }

    /// 모두 삭제 — diagnostics export 등에 사용.
    public func dismissAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        for url in entries where url.pathExtension == "json" {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
