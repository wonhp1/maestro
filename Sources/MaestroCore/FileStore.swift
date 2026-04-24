import Foundation

/// Codable 값 단일을 JSON 파일로 원자적 저장/로드하는 actor.
///
/// - 원자적 쓰기: `Data.write(to:options:.atomic)` 가 temp + rename 으로 보장.
/// - 동시성: actor 로 직렬화 — 같은 `FileStore` 인스턴스에 대한 동시 호출은 큐잉.
/// - 디스크 포맷: `JSONEncoder.maestro` / `JSONDecoder.maestro`.
///
/// ## 범위
/// "값 하나 = 파일 하나" 저장 전용. 대화 로그처럼 append-only 인 경우 `JSONLAppender`
/// 를 쓸 것.
///
/// - Phase 4+ 의 레지스트리 / 설정 파일에 사용.
public actor FileStore<T: Codable & Sendable> {
    public let path: URL
    private let fileManager: FileManager

    public init(path: URL, fileManager: FileManager = .default) {
        self.path = path
        self.fileManager = fileManager
    }

    public func exists() -> Bool {
        fileManager.fileExists(atPath: path.path)
    }

    public func load() throws -> T {
        guard fileManager.fileExists(atPath: path.path) else {
            throw PersistenceError.fileNotFound(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw PersistenceError.atomicWriteFailed(path: path, underlying: "\(error)")
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
    }

    public func delete() throws {
        guard fileManager.fileExists(atPath: path.path) else { return }
        try fileManager.removeItem(at: path)
    }

    private func ensureParentDirectoryExists() throws {
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
