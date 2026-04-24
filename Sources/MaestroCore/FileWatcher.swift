import Dispatch
import Foundation

/// `DispatchSource` 기반 파일/디렉토리 변경 감시.
///
/// - AsyncStream 반환 — `for await event in watcher.events(for:)` 로 소비.
/// - 스트림 종료 시 dispatch source 자동 취소 (파일 디스크립터 누수 없음).
/// - 감시 이벤트: write / delete / rename / attributes.
///
/// ## ⚠️ 이벤트 Coalescing 주의
/// `DispatchSource.FileSystemObjectSource` 는 **같은 이벤트를 합쳐서 한 번만**
/// 발행한다. 예를 들어 50번 write 가 짧은 시간 안에 발생하면 `.writeCompleted`
/// 는 **1번만** yield 된다.
///
/// **소비자 규약**: 이벤트 수를 세지 말 것. 이벤트는 "변화가 일어났다" 신호일 뿐,
/// 실제 변화를 보려면 파일 상태를 다시 읽어야 함 (이것이 `JSONLTailer` 의 offset
/// 기반 재드레인이 올바른 이유).
///
/// ## ⚠️ Rename / Atomic Replace 에 취약
/// `FileStore.save` 는 write-to-tmp → rename 으로 원본 파일을 교체한다. 이때 기존
/// 파일의 inode 는 삭제되고 새 inode 로 대체된다. `FileWatcher` 가 쥔 fd 는 **삭제된
/// inode** 를 계속 가리킨다 — `.delete`/`.rename` 이벤트가 발생하지만 이후 write 는
/// **감지되지 않음**.
///
/// **대응**: `.delete`/`.rename` 이벤트를 받으면 상위 레이어가 watcher 재시작 필요.
/// 또는 디렉토리 레벨 감시 (Phase 11 `InboxWatcher` 에서 구현 예정).
public enum FileWatcher {
    /// 지정 경로를 감시. 파일이 존재해야 함 (없으면 즉시 `finish`).
    public static func events(for path: URL) -> AsyncStream<FileWatchEvent> {
        AsyncStream { continuation in
            let fd = open(path.path, O_EVTONLY | O_CLOEXEC)
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
                if flags.contains(.delete) {
                    continuation.yield(.deleted)
                    continuation.finish()  // inode 삭제 후 fd 는 무용지물.
                }
                if flags.contains(.rename) {
                    continuation.yield(.renamed)
                    continuation.finish()  // 원본 inode 가 아닌 것을 감시하게 됨.
                }
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
