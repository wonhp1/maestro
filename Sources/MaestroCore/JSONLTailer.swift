import Dispatch
import Foundation

/// JSONL 파일을 증분으로 tail 하여 새로 append 된 항목을 디코드 후 AsyncThrowingStream 으로 발행.
///
/// - 파일이 커져도 O(증분만큼) — 매번 처음부터 읽지 않음.
/// - `DispatchSource.makeFileSystemObjectSource` 로 write 감지.
/// - 시작 offset 지정 가능 (기본: 파일 끝 = 기존 히스토리 건너뜀).
/// - Phase 11 `InboxWatcher` 의 기반.
///
/// ## 방어 한계
/// - `maxPartialLineBytes` 초과 시 `resourceLimitExceeded` — 무한 growing 라인 OOM 방어.
/// - `chunkSize` 단위로 분할 읽기 — 한 번에 100MB delta 를 메모리에 담지 않음.
/// - Truncation 감지: 현재 파일 크기가 `offset` 보다 작으면 `offset = 0`, partial 비움.
/// - 디코드 실패 시 source 취소 + stream finish.
///
/// ## 주의: DispatchSource 이벤트 coalescing
/// `source.data` 는 여러 write 를 한 이벤트로 합침. 이 타입은 offset 기반 재드레인
/// 으로 이 문제 없음. 단, `FileWatcher` 이벤트 소비자는 1:1 매핑 가정 금지.
public actor JSONLTailer<T: Codable & Sendable> {
    public static var defaultMaxPartialLineBytes: Int { 16 * 1024 * 1024 }  // 16 MiB
    public static var defaultChunkSize: Int { 64 * 1024 }                     // 64 KiB

    public let path: URL
    public let maxPartialLineBytes: Int
    public let chunkSize: Int

    public init(
        path: URL,
        maxPartialLineBytes: Int = JSONLTailer.defaultMaxPartialLineBytes,
        chunkSize: Int = JSONLTailer.defaultChunkSize
    ) {
        self.path = path
        self.maxPartialLineBytes = maxPartialLineBytes
        self.chunkSize = chunkSize
    }

    /// 현재 offset 이후 새로 append 되는 이벤트를 발행.
    ///
    /// - `fromByteOffset: nil` 이면 파일 끝부터 (새 이벤트만).
    /// - `fromByteOffset: 0` 이면 기존 내용 전부 + 이후 신규.
    nonisolated public func events(
        fromByteOffset startOffset: UInt64? = nil
    ) -> AsyncThrowingStream<T, Error> {
        let path = self.path
        let maxPartial = self.maxPartialLineBytes
        let chunkSize = self.chunkSize
        return AsyncThrowingStream { continuation in
            let fileManager = FileManager.default

            // 파일이 없으면 만들어놓음 — watcher 는 존재하는 FD 만 감시 가능.
            if !fileManager.fileExists(atPath: path.path) {
                fileManager.createFile(atPath: path.path, contents: nil)
            }

            let fd = open(path.path, O_EVTONLY | O_CLOEXEC)
            guard fd != -1 else {
                continuation.finish(throwing: PersistenceError.watcherStartFailed(path))
                return
            }

            let queue = DispatchQueue(label: "maestro.jsonl-tailer", qos: .utility)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend],
                queue: queue
            )

            let state = TailState<T>(
                path: path,
                offset: startOffset ?? ((try? currentSize(of: path)) ?? 0),
                maxPartialBytes: maxPartial,
                chunkSize: chunkSize
            )

            let cancelOnError: @Sendable (Error) -> Void = { error in
                source.cancel()
                continuation.finish(throwing: error)
            }

            source.setEventHandler {
                do {
                    try state.drainAndEmit(continuation: continuation)
                } catch {
                    cancelOnError(error)
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()

            // 초기 drain (startOffset=0 인 경우 기존 내용 flush)
            do {
                try state.drainAndEmit(continuation: continuation)
            } catch {
                cancelOnError(error)
                return
            }

            continuation.onTermination = { @Sendable _ in
                source.cancel()
            }
        }
    }
}

/// 파일 크기 조회 헬퍼.
private func currentSize(of path: URL) throws -> UInt64 {
    let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
    return (attrs[.size] as? UInt64) ?? 0
}

/// 증분 읽기 상태. DispatchSource 핸들러에서 공유.
///
/// 참조 타입(class)인 이유: DispatchSource 핸들러에서 캡처 후 상태 갱신.
/// Sendable 준수는 내부 lock 으로 직렬화 (동시 호출은 실제로 single queue 에서만 옴).
private final class TailState<T: Codable & Sendable>: @unchecked Sendable {
    private let path: URL
    private let maxPartialBytes: Int
    private let chunkSize: Int
    private var offset: UInt64
    private var partial: Data = Data()
    private let lock = NSLock()
    private let decoder = JSONDecoder.maestro

    init(path: URL, offset: UInt64, maxPartialBytes: Int, chunkSize: Int) {
        self.path = path
        self.offset = offset
        self.maxPartialBytes = maxPartialBytes
        self.chunkSize = chunkSize
    }

    func drainAndEmit(continuation: AsyncThrowingStream<T, Error>.Continuation) throws {
        lock.lock()
        defer { lock.unlock() }

        // Truncation 감지 — 현재 크기가 offset 보다 작으면 파일이 축소/재생성됨.
        let currentFileSize: UInt64
        do {
            currentFileSize = try currentSize(of: path)
        } catch {
            throw PersistenceError.readFailed(path: path, underlying: "\(error)")
        }
        if currentFileSize < offset {
            offset = 0
            partial.removeAll(keepingCapacity: false)
        }

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: path)
        } catch {
            throw PersistenceError.readFailed(path: path, underlying: "\(error)")
        }
        defer { try? fileHandle.close() }

        do {
            try fileHandle.seek(toOffset: offset)
        } catch {
            // 어떤 이유로든 seek 실패 시 처음부터 재시도.
            offset = 0
            partial.removeAll(keepingCapacity: false)
            try? fileHandle.seek(toOffset: 0)
        }

        // 청크 단위로 증분 읽기 — 100MB delta 도 메모리 폭발 없이 처리.
        while true {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            partial.append(chunk)
            offset += UInt64(chunk.count)

            try processPartialAndEmit(continuation: continuation)

            if chunk.count < chunkSize { break }  // EOF 도달
        }
    }

    private func processPartialAndEmit(
        continuation: AsyncThrowingStream<T, Error>.Continuation
    ) throws {
        var lineStart = partial.startIndex
        var searchIndex = partial.startIndex
        while let newlineIdx = partial[searchIndex...].firstIndex(of: 0x0A) {
            let lineData = partial[lineStart..<newlineIdx]
            if !lineData.isEmpty {
                do {
                    let value = try decoder.decode(T.self, from: lineData)
                    continuation.yield(value)
                } catch {
                    throw PersistenceError.decodingFailed(
                        path: path, underlying: "\(error)"
                    )
                }
            }
            let nextIdx = partial.index(after: newlineIdx)
            lineStart = nextIdx
            searchIndex = nextIdx
        }

        // 처리한 만큼 파편 버퍼에서 제거
        if lineStart > partial.startIndex {
            partial = partial[lineStart..<partial.endIndex]
        }

        // partial 이 한계 초과 → 무한 growing 라인 방어.
        if partial.count > maxPartialBytes {
            throw PersistenceError.resourceLimitExceeded(
                path: path, limit: maxPartialBytes, actual: partial.count
            )
        }
    }
}
