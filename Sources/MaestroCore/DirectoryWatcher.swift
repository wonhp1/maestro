import Dispatch
import Foundation

/// 디렉토리 변경 감시 — 자식 항목 추가/삭제/변경 시 이벤트 emit.
///
/// `FileWatcher` 와 형제. 차이점:
/// - 파일 → 디렉토리 fd 감시 (`O_EVTONLY` on dir).
/// - `.write` 이벤트가 자식 add/remove/rename 시 발생 (디렉토리 mtime 변경).
///
/// ## 사용 패턴 (Phase 11 InboxWatcher)
/// ```swift
/// let stream = DirectoryWatcher.events(for: inboxDir)
/// for await _ in stream {
///     // 디렉토리 변화 감지 — 실제 변화는 readdir 로 다시 확인.
/// }
/// ```
///
/// ## Coalescing 규약
/// `FileWatcher` 와 동일: `DispatchSource` 가 같은 이벤트를 합침. 이벤트 수 ≠ 변화
/// 수. 소비자는 readdir 로 다시 스캔해야 함.
///
/// ## Self-deletion
/// 감시 중인 디렉토리 자체가 삭제/이동되면 `.deleted` / `.renamed` emit 후 stream
/// finish. 호출자가 재개해야 함.
///
/// ## 보안
/// 감시는 fd 만 들고 있음 — 디렉토리 내용을 읽지 않음. 권한 영향 없음.
public enum DirectoryWatcher {
    /// 지정 디렉토리를 감시. 디렉토리가 존재해야 함 (없으면 즉시 finish).
    public static func events(for directory: URL) -> AsyncStream<DirectoryWatchEvent> {
        AsyncStream { continuation in
            let fd = open(directory.path, O_EVTONLY | O_CLOEXEC)
            guard fd != -1 else {
                continuation.finish()
                return
            }

            let queue = DispatchQueue.global(qos: .utility)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename],
                queue: queue
            )
            source.setEventHandler {
                let flags = source.data
                if flags.contains(.write) { continuation.yield(.changed) }
                if flags.contains(.delete) {
                    continuation.yield(.deleted)
                    continuation.finish()
                }
                if flags.contains(.rename) {
                    continuation.yield(.renamed)
                    continuation.finish()
                }
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

public enum DirectoryWatchEvent: Sendable, Equatable {
    /// 디렉토리 내부에 변화 (자식 add/remove/rename, 메타 변경).
    case changed
    /// 디렉토리 자체 삭제. stream finish 됨.
    case deleted
    /// 디렉토리 자체 rename. stream finish 됨.
    case renamed
}
