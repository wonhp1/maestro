import Foundation

/// 봉투 (`MessageEnvelope`) 디스크 저장 / 로드 / 이동 / 삭제 — actor 직렬화.
///
/// ## 책임 / 비책임
/// - **책임**: 단일 봉투 → 단일 JSON 파일 ↔ 안전한 atomic 쓰기 + 0600 perms.
/// - **비책임**: 디렉토리 감시 (DirectoryWatcher), 라우팅 결정 (EnvelopeRouter),
///   thread 누적 (ThreadLogger).
///
/// ## 동시성 + 내구성
/// - actor 직렬화로 같은 인스턴스 동시 호출 안전.
/// - `Data.write(to:options: .atomic)` — temp + rename(2) atomicity.
/// - **fsync 디렉토리 미보장** (FileStore 와 동일 한계). 크래시 직후 rename 이 디스크에
///   미반영된 채 사라질 가능성 — Phase 11 router 의 at-least-once 시맨틱은 inbox/
///   감시 + replay 로 보완 (router 가 재시작 시 inbox 재스캔).
///
/// ## 보안
/// - 모든 봉투 파일은 `0600` (소유자만 읽기/쓰기). Phase 9 의 chat-history 패턴.
/// - 부모 디렉토리는 `0700` (다른 로컬 사용자 차단).
/// - **크기 제한**: load 시 `maxFileSize` (기본 4 MiB) 검증 — 손상/악의적 거대 파일
///   OOM 방어. envelope.body 가 256 KiB (ChatViewModel cap) + 메타 → 4 MiB 충분.
public actor EnvelopeStorage {
    public static var defaultMaxFileSize: Int { 4 * 1024 * 1024 }

    private let fileManager: FileManager
    public let maxFileSize: Int

    public init(
        fileManager: FileManager = .default,
        maxFileSize: Int = EnvelopeStorage.defaultMaxFileSize
    ) {
        self.fileManager = fileManager
        self.maxFileSize = maxFileSize
    }

    /// 봉투를 atomic write. 부모 디렉토리 자동 생성 + perms 적용.
    public func write(_ envelope: MessageEnvelope, to path: URL) throws {
        try ensureParentDirectoryExists(of: path)
        let data: Data
        do {
            data = try JSONEncoder.maestro.encode(envelope)
        } catch {
            throw PersistenceError.encodingFailed(path: path, underlying: "\(error)")
        }
        do {
            try data.write(to: path, options: [.atomic])
        } catch {
            throw PersistenceError.atomicWriteFailed(path: path, underlying: "\(error)")
        }
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: path.path
        )
    }

    /// 디스크에서 봉투 로드. 크기/디코드 검증.
    public func read(from path: URL) throws -> MessageEnvelope {
        guard fileManager.fileExists(atPath: path.path) else {
            throw PersistenceError.fileNotFound(path)
        }
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
            return try JSONDecoder.maestro.decode(MessageEnvelope.self, from: data)
        } catch {
            throw PersistenceError.decodingFailed(path: path, underlying: "\(error)")
        }
    }

    /// 봉투 파일 이동 (예: inbox → failed DLQ). 대상 부모 자동 생성.
    /// **0600 perms 를 이동 후 재적용** — 외부에서 drop 된 0644 파일이 DLQ 에 0644
    /// 로 남는 것을 방어 (보안 must-fix).
    public func move(from source: URL, to destination: URL) throws {
        try ensureParentDirectoryExists(of: destination)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: destination.path
        )
    }

    /// 봉투 파일 삭제. 없으면 no-op.
    public func delete(at path: URL) throws {
        guard fileManager.fileExists(atPath: path.path) else { return }
        try fileManager.removeItem(at: path)
    }

    public func exists(at path: URL) -> Bool {
        fileManager.fileExists(atPath: path.path)
    }

    private func ensureParentDirectoryExists(of path: URL) throws {
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: parent.path
        )
    }
}
