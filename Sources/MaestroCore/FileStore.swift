import Foundation

/// Codable 값 단일을 JSON 파일로 원자적 저장/로드하는 actor.
///
/// - 원자적 쓰기: `Data.write(to:options:.atomic)` 가 temp + rename 으로 보장.
/// - 동시성: actor 로 직렬화 — 같은 `FileStore` 인스턴스에 대한 동시 호출은 큐잉.
/// - 디스크 포맷: `JSONEncoder.maestro` / `JSONDecoder.maestro`.
/// - **파일 권한**: 저장 후 `chmod 0600` — 다른 로컬 사용자의 읽기 차단.
/// - **크기 제한**: 로드 시 기본 10 MiB 상한 — 손상/악의적 파일 OOM 방어.
///
/// ## 범위
/// "값 하나 = 파일 하나" 저장 전용. 대화 로그처럼 append-only 인 경우 `JSONLAppender`
/// 를 쓸 것.
///
/// ## 내구성 한계 (현재)
/// `.atomic` 옵션은 rename(2) atomicity 만 보장. 실제 rename 후 디렉토리 fsync 는
/// 안 함 — 크래시 직후 복구 시 파일이 사라져 보일 가능성 이론상 존재. 단, 다음 쓰기
/// 가 성공하면 복구. Phase 11 router 에서 크래시 복구 시나리오 발견되면 fsync 추가.
public actor FileStore<T: Codable & Sendable> {
    public static var defaultMaxFileSize: Int { 10 * 1024 * 1024 }  // 10 MiB

    public let path: URL
    public let maxFileSize: Int
    private let fileManager: FileManager

    public init(
        path: URL,
        maxFileSize: Int = FileStore.defaultMaxFileSize,
        fileManager: FileManager = .default
    ) {
        self.path = path
        self.maxFileSize = maxFileSize
        self.fileManager = fileManager
    }

    public func exists() -> Bool {
        fileManager.fileExists(atPath: path.path)
    }

    public func load() throws -> T {
        guard fileManager.fileExists(atPath: path.path) else {
            throw PersistenceError.fileNotFound(path)
        }
        // 크기 선검증 — OOM/DoS 방어.
        if let size = try? fileManager.attributesOfItem(atPath: path.path)[.size] as? Int,
           size > maxFileSize {
            throw PersistenceError.resourceLimitExceeded(
                path: path, limit: maxFileSize, actual: size
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw PersistenceError.readFailed(path: path, underlying: "\(error)")
        }
        do {
            return try JSONDecoder.maestro.decode(T.self, from: data)
        } catch {
            throw PersistenceError.decodingFailed(path: path, underlying: "\(error)")
        }
    }

    public func loadIfExists() throws -> T? {
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        return try load()
    }

    public func save(_ value: T) throws {
        try ensureParentDirectoryExists()
        let data: Data
        do {
            data = try JSONEncoder.maestro.encode(value)
        } catch {
            throw PersistenceError.encodingFailed(path: path, underlying: "\(error)")
        }
        do {
            try data.write(to: path, options: [.atomic])
        } catch {
            throw PersistenceError.atomicWriteFailed(path: path, underlying: "\(error)")
        }
        // 파일 권한 0600 — 소유자만 읽기/쓰기.
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: path.path
        )
    }

    public func delete() throws {
        guard fileManager.fileExists(atPath: path.path) else { return }
        try fileManager.removeItem(at: path)
    }

    private func ensureParentDirectoryExists() throws {
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        // 부모 디렉토리 권한 0700 — 다른 로컬 사용자 접근 차단.
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: parent.path
        )
    }
}
