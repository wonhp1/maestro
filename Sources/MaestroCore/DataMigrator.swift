import Foundation

/// 사용자 데이터 schema 의 단일 정수 버전.
///
/// 새 스키마 변경마다 +1. v0 = pre-Phase-23 baseline (마이그레이션 필요 없음).
public struct SchemaVersion: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let value: Int

    public init(_ value: Int) {
        self.value = max(0, value)
    }

    public static let v0 = SchemaVersion(0)
    public static let current = SchemaVersion(0)

    public var description: String { "v\(value)" }
    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.value < rhs.value
    }
}

/// 단일 마이그레이션 step. `from → to` (반드시 to == from + 1).
public protocol DataMigrator: Sendable {
    var from: SchemaVersion { get }
    var to: SchemaVersion { get }
    func migrate() async throws
}

/// `SchemaVersion` 추적 + 등록된 migrator 들 순서대로 실행.
///
/// ## 동작
/// 1. `currentVersion()` — 디스크 파일에서 읽음 (없으면 v0).
/// 2. `migrateIfNeeded()` — current → target 까지 step 별 migrator 실행.
///    각 step 성공 시 즉시 디스크 버전 bump (재시작 시 이어서 가능).
/// 3. step 실패 → throws + 부분 진행 상태 보존 (사용자 보고 + 롤백 가능).
///
/// ## 보안
/// - `versionFile` 은 0600 권한 (FileStore 와 동일).
/// - 각 migrator 는 자체 atomicity 책임.
public actor DataMigrationCoordinator {
    public let versionFile: URL
    public let target: SchemaVersion
    private var migrators: [DataMigrator] = []

    public init(versionFile: URL, target: SchemaVersion = .current) {
        self.versionFile = versionFile
        self.target = target
    }

    public func register(_ migrator: DataMigrator) {
        migrators.append(migrator)
    }

    public func currentVersion() throws -> SchemaVersion {
        guard FileManager.default.fileExists(atPath: versionFile.path) else {
            return .v0
        }
        let data = try Data(contentsOf: versionFile)
        return try JSONDecoder.maestro.decode(SchemaVersion.self, from: data)
    }

    public func setVersion(_ version: SchemaVersion) throws {
        try FileManager.default.createDirectory(
            at: versionFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.maestro.encode(version)
        try data.write(to: versionFile, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: versionFile.path
        )
    }

    @discardableResult
    public func migrateIfNeeded() async throws -> [SchemaVersion] {
        var current = try currentVersion()
        if current >= target { return [] }
        var executed: [SchemaVersion] = []
        let sorted = migrators.sorted { $0.from < $1.from }
        while current < target {
            guard let next = sorted.first(where: { $0.from == current }) else {
                throw DataMigrationError.missingMigrator(from: current)
            }
            guard next.to == SchemaVersion(current.value + 1) else {
                throw DataMigrationError.invalidStep(from: next.from, to: next.to)
            }
            try await next.migrate()
            try setVersion(next.to)
            executed.append(next.to)
            current = next.to
        }
        return executed
    }
}

public enum DataMigrationError: Error, Equatable, Sendable {
    case missingMigrator(from: SchemaVersion)
    case invalidStep(from: SchemaVersion, to: SchemaVersion)
}
