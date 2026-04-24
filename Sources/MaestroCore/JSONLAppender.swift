import Foundation

/// JSONL (한 줄 당 JSON 하나) 파일에 append-only 쓰기를 담당하는 actor.
///
/// - `Thread` 스레드 로그, envelope 이력 등 누적 저장 전용.
/// - 동시성: 같은 `JSONLAppender` 인스턴스는 actor 로 직렬화.
/// - **주의**: 여러 프로세스가 같은 파일에 쓰면 line 이 섞일 수 있음 (Phase 3 MVP 는
///   단일 프로세스 전제). 추후 fcntl(F_SETLK) 추가 고려.
///
/// - 포맷: `JSONEncoder.maestro` 로 인코딩 후 `\n` 구분자 추가.
public actor JSONLAppender<T: Codable & Sendable> {
    public let path: URL
    private let fileManager: FileManager

    public init(path: URL, fileManager: FileManager = .default) {
        self.path = path
        self.fileManager = fileManager
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

        // append 모드로 열기 (없으면 생성). 쓰기 실패 시 throw.
        if !fileManager.fileExists(atPath: path.path) {
            fileManager.createFile(atPath: path.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: path) else {
            throw PersistenceError.atomicWriteFailed(
                path: path, underlying: "파일 핸들 열기 실패"
            )
        }
        defer { try? handle.close() }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: buffer)
        } catch {
            throw PersistenceError.atomicWriteFailed(path: path, underlying: "\(error)")
        }
    }

    /// 현재 파일 크기 (바이트). Tailer 가 시작 offset 을 정하는 데 사용.
    public func currentByteSize() throws -> UInt64 {
        guard fileManager.fileExists(atPath: path.path) else { return 0 }
        let attrs = try fileManager.attributesOfItem(atPath: path.path)
        return (attrs[.size] as? UInt64) ?? 0
    }

    private func ensureParentDirectoryExists() throws {
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
