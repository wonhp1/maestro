import Dispatch
import Foundation

/// JSONL 파일을 증분으로 tail 하여 새로 append 된 항목을 디코드 후 AsyncThrowingStream 으로 발행.
///
/// - 파일이 커져도 O(증분만큼) — 매번 처음부터 읽지 않음.
/// - `DispatchSource.makeFileSystemObjectSource` 로 write 감지.
/// - 시작 offset 지정 가능 (기본: 파일 끝 = 기존 히스토리 건너뜀).
/// - Phase 11 `InboxWatcher` 의 기반.
public actor JSONLTailer<T: Codable & Sendable> {
    public let path: URL

    public init(path: URL) {
        self.path = path
    }

    /// 현재 offset 이후 새로 append 되는 이벤트를 발행.
    ///
    /// - `fromByteOffset: nil` 이면 파일 끝부터 (새 이벤트만).
    /// - `fromByteOffset: 0` 이면 기존 내용 전부 + 이후 신규.
    nonisolated public func events(
        fromByteOffset startOffset: UInt64? = nil
    ) -> AsyncThrowingStream<T, Error> {
        let path = self.path
        return AsyncThrowingStream { continuation in
            let fileManager = FileManager.default

            // 파일이 없으면 만들어놓음 — watcher 는 존재하는 FD 만 감시 가능.
            if !fileManager.fileExists(atPath: path.path) {
                fileManager.createFile(atPath: path.path, contents: nil)
            }

            let fd = open(path.path, O_EVTONLY)
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

            // 상태 (actor-style self-contained)
            let state = TailState<T>(
                path: path,
                offset: startOffset ?? ((try? currentSize(of: path)) ?? 0)
            )

            source.setEventHandler {
                do {
                    try state.drainAndEmit(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
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
                continuation.finish(throwing: error)
                return
            }

            continuation.onTermination = { @Sendable _ in
                source.cancel()
            }
        }
    }
}

// 파일 크기 조회 헬퍼.
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
    private var offset: UInt64
    private var partial: Data = Data()
    private let lock = NSLock()
    private let decoder = JSONDecoder.maestro

    init(path: URL, offset: UInt64) {
        self.path = path
        self.offset = offset
    }

    func drainAndEmit(continuation: AsyncThrowingStream<T, Error>.Continuation) throws {
        lock.lock()
        defer { lock.unlock() }

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: path)
        } catch {
            throw PersistenceError.atomicWriteFailed(path: path, underlying: "\(error)")
        }
        defer { try? fileHandle.close() }

        do {
            try fileHandle.seek(toOffset: offset)
        } catch {
            // 파일이 truncate 된 경우 offset 을 0 으로 리셋
            offset = 0
            try? fileHandle.seek(toOffset: 0)
        }

        let newChunk = fileHandle.readDataToEndOfFile()
        if newChunk.isEmpty { return }

        partial.append(newChunk)
        offset += UInt64(newChunk.count)

        // 완성된 줄(\n 로 끝남)만 파싱. 마지막 불완전 줄은 partial 에 남김.
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
    }
}
