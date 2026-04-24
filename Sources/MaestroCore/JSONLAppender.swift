import Foundation

/// JSONL (한 줄 당 JSON 하나) 파일에 append-only 쓰기를 담당하는 actor.
///
/// - `Thread` 스레드 로그, envelope 이력 등 누적 저장 전용.
/// - 동시성: 같은 `JSONLAppender` 인스턴스는 actor 로 직렬화 — line 이 섞이지 않음.
/// - **멀티 프로세스**: fcntl 락 없음. 현재는 단일 프로세스 전제 (앱 또는 CLI 둘 중
///   하나만 쓰기). Phase 4+ 에서 flock 추가 고려.
///
/// ## 성능
/// FileHandle 을 최초 append 시 열고 actor 수명 동안 재사용 — 매 append 마다 open/
/// close syscall 회피. `close()` 명시 호출 또는 deinit 에서 정리.
///
/// ## 내구성
/// `synchronize: true` (기본값) 면 매 append 후 fsync — 크래시해도 append 된 라인
/// 손실 없음. Phase 11 router 의 at-least-once 요구사항 충족. 성능이 문제면
/// `synchronize: false` 로 명시 opt-out 가능.
///
/// ## 파일 권한
/// 새로 만들 때 `0600` (소유자만 읽기/쓰기).
public actor JSONLAppender<T: Codable & Sendable> {
    public let path: URL
    public let synchronize: Bool
    private let fileManager: FileManager

    private var cachedHandle: FileHandle?

    public init(
        path: URL,
        synchronize: Bool = true,
        fileManager: FileManager = .default
    ) {
        self.path = path
        self.synchronize = synchronize
        self.fileManager = fileManager
    }

    deinit {
        try? cachedHandle?.close()
    }

    public func append(_ value: T) throws {
        try appendAll([value])
    }

    public func appendAll(_ values: [T]) throws {
        guard !values.isEmpty else { return }

        try ensureParentDirectoryExists()

        // 인코딩 단계 (디스크 쓰기 전 모든 검증 통과 확인)
        var buffer = Data()
        let encoder = JSONEncoder.maestro
        for value in values {
            let data: Data
            do {
                data = try encoder.encode(value)
            } catch {
                throw PersistenceError.encodingFailed(path: path, underlying: "\(error)")
            }
            buffer.append(data)
            buffer.append(0x0A) // '\n'
        }

        let handle = try acquireHandle()
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: buffer)
            if synchronize {
                try handle.synchronize()  // fsync(2) — 크래시 대응
            }
        } catch {
            // 실패 시 핸들 무효화 — 다음 호출에서 재오픈.
            try? cachedHandle?.close()
            cachedHandle = nil
            throw PersistenceError.atomicWriteFailed(path: path, underlying: "\(error)")
        }
    }

    /// 현재 파일 크기 (바이트). Tailer 가 시작 offset 을 정하는 데 사용.
    public func currentByteSize() throws -> UInt64 {
        guard fileManager.fileExists(atPath: path.path) else { return 0 }
        let attrs = try fileManager.attributesOfItem(atPath: path.path)
        return (attrs[.size] as? UInt64) ?? 0
    }

    /// 명시적으로 핸들 닫기. 장기 앱이라면 필요 없으나, 테스트 / 명시적 자원 정리용.
    public func close() {
        try? cachedHandle?.close()
        cachedHandle = nil
    }

    private func acquireHandle() throws -> FileHandle {
        if let handle = cachedHandle { return handle }

        if !fileManager.fileExists(atPath: path.path) {
            fileManager.createFile(
                atPath: path.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
            )
        } else {
            // 기존 파일도 권한 0600 강제 (legacy 파일 보정).
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: path.path
            )
        }

        do {
            let handle = try FileHandle(forWritingTo: path)
            cachedHandle = handle
            return handle
        } catch {
            throw PersistenceError.atomicWriteFailed(
                path: path, underlying: "파일 핸들 열기 실패: \(error)"
            )
        }
    }

    private func ensureParentDirectoryExists() throws {
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: parent.path
        )
    }
}
