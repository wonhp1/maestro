import Dispatch
import Foundation

/// `DispatchSource` 기반 파일/디렉토리 변경 감시.
///
/// - AsyncStream 반환 — `for await event in watcher.events(for:)` 로 소비.
/// - 스트림 종료 시 dispatch source 자동 취소 (파일 디스크립터 누수 없음).
/// - 감시 이벤트: write / delete / rename / attributes.
public enum FileWatcher {
    /// 지정 경로를 감시. 파일이 존재해야 함 (없으면 즉시 `finish`).
    public static func events(for path: URL) -> AsyncStream<FileWatchEvent> {
        AsyncStream { continuation in
            let fd = open(path.path, O_EVTONLY)
            guard fd != -1 else {
                continuation.finish()
                return
            }

            let queue = DispatchQueue.global(qos: .utility)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .attrib],
                queue: queue
            )

            source.setEventHandler {
                let flags = source.data
                if flags.contains(.write) { continuation.yield(.writeCompleted) }
                if flags.contains(.delete) { continuation.yield(.deleted) }
                if flags.contains(.rename) { continuation.yield(.renamed) }
                if flags.contains(.attrib) { continuation.yield(.attributesChanged) }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()

            continuation.onTermination = { @Sendable _ in
                source.cancel()
            }
        }
    }
}

/// 파일 감시에서 발생 가능한 이벤트 유형.
public enum FileWatchEvent: Sendable, Equatable {
    case writeCompleted
    case deleted
    case renamed
    case attributesChanged
}
