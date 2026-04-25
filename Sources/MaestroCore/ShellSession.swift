import Foundation

/// PTY 기반 쉘 세션 추상화 — 사용자 입력/출력 + lifecycle.
///
/// 구현체는 `Sendable` actor — 동시 read/write 안전.
public protocol ShellSession: Sendable {
    /// 쉘 프로세스 spawn. 호출 후 `events` 가 yield 시작.
    func start() async throws

    /// 키보드 입력을 master fd 에 write.
    func send(_ data: Data) async

    /// 터미널 크기 변경. SIGWINCH 자동 전달.
    func resize(cols: Int, rows: Int) async

    /// SIGTERM 후 grace 기간 후 SIGKILL. start 안 됐어도 안전.
    func terminate() async

    /// 출력 + lifecycle 이벤트 stream.
    /// 한 세션당 한 번만 의미 (multi-subscriber 지원 X).
    var events: AsyncStream<ShellSessionEvent> { get async }
}

public enum ShellSessionEvent: Sendable, Equatable {
    /// PTY master 에서 읽은 raw bytes (UTF-8 가정 안 함 — 클라가 파싱).
    case output(Data)
    /// 자식 프로세스 종료 (exit code 또는 시그널 번호).
    case exited(code: Int32)
    /// 시작 / read 실패.
    case error(message: String)
}

public enum ShellSessionError: Error, Equatable, Sendable {
    case forkpty(errno: Int32)
    case execFailed(errno: Int32)
    case alreadyStarted
    case notStarted
}
