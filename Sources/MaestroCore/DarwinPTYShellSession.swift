import Darwin
import Dispatch
import Foundation

/// Darwin `forkpty(3)` 기반 `ShellSession` 구현.
///
/// ## 동작
/// 1. `start()` — `forkpty` 로 자식 프로세스 + master fd 생성. 자식은 지정된 shell 을
///    `execve`. master fd 를 DispatchSourceRead 로 감시 → output stream yield.
/// 2. `send()` — master fd 에 직접 write.
/// 3. `resize()` — `ioctl(TIOCSWINSZ)` + 자식에게 자동 SIGWINCH (커널 전달).
/// 4. `terminate()` — SIGTERM → 100ms 후에도 살아있으면 SIGKILL. fd close + waitpid.
///
/// ## 보안
/// - exec arg 는 hardcoded shell path. 사용자 입력 X.
/// - 환경변수는 호출자 sanitize 후 전달 (기본은 호출 프로세스 환경 상속).
/// - master fd 는 actor 안에서만 보관. close 후 재사용 X.
///
/// ## 동시성
/// actor 직렬화. read 는 background DispatchQueue.
public actor DarwinPTYShellSession: ShellSession {
    public let executablePath: String
    public let arguments: [String]
    public let workingDirectory: URL?
    public let initialCols: Int
    public let initialRows: Int

    private var primaryFD: Int32 = -1
    private var childPID: pid_t = -1
    private var readSource: DispatchSourceRead?
    private var continuation: AsyncStream<ShellSessionEvent>.Continuation?
    private var stream: AsyncStream<ShellSessionEvent>?
    private var started: Bool = false
    private var terminated: Bool = false

    public init(
        executablePath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        arguments: [String] = ["-l"],
        workingDirectory: URL? = nil,
        initialCols: Int = 80,
        initialRows: Int = 24
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.initialCols = max(1, initialCols)
        self.initialRows = max(1, initialRows)
    }

    public var events: AsyncStream<ShellSessionEvent> {
        get async {
            if let stream { return stream }
            let stream = AsyncStream<ShellSessionEvent> { continuation in
                self.continuation = continuation
            }
            self.stream = stream
            return stream
        }
    }

    public func start() async throws {
        guard !started else { throw ShellSessionError.alreadyStarted }
        // events stream 활성화
        _ = await events
        var win = winsize(
            ws_row: UInt16(initialRows),
            ws_col: UInt16(initialCols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        var primaryArg: Int32 = -1
        let pid = withUnsafeMutablePointer(to: &win) { winPtr -> pid_t in
            forkpty(&primaryArg, nil, nil, winPtr)
        }
        if pid < 0 {
            throw ShellSessionError.forkpty(errno: errno)
        }
        if pid == 0 {
            // child
            if let cwd = workingDirectory {
                _ = cwd.path.withCString { chdir($0) }
            }
            // exec — leak fd 는 OS 가 정리 (process replace).
            let argv: [UnsafeMutablePointer<CChar>?] = ([executablePath] + arguments).map {
                strdup($0)
            } + [nil]
            defer { argv.forEach { free($0) } }
            execv(executablePath, argv)
            // exec 실패
            _ = "exec failed\n".withCString { write(2, $0, strlen($0)) }
            exit(127)
        }
        // parent
        primaryFD = primaryArg
        childPID = pid
        started = true
        startReadSource()
    }

    public func send(_ data: Data) async {
        guard started, primaryFD >= 0 else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var remaining = buffer.count
            var ptr = base
            while remaining > 0 {
                let written = write(primaryFD, ptr, remaining)
                if written <= 0 { return }
                ptr = ptr.advanced(by: written)
                remaining -= written
            }
        }
    }

    public func resize(cols: Int, rows: Int) async {
        guard started, primaryFD >= 0 else { return }
        var win = winsize(
            ws_row: UInt16(max(1, rows)),
            ws_col: UInt16(max(1, cols)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(primaryFD, tiocswinszRequest, &win)
    }

    public func terminate() async {
        guard started, !terminated else { return }
        terminated = true
        readSource?.cancel()
        readSource = nil
        if childPID > 0 {
            _ = kill(childPID, SIGTERM)
            // grace
            try? await Task.sleep(nanoseconds: 100_000_000)
            var status: Int32 = 0
            let waited = waitpid(childPID, &status, WNOHANG)
            if waited == 0 {
                _ = kill(childPID, SIGKILL)
                _ = waitpid(childPID, &status, 0)
            }
            continuation?.yield(.exited(code: status))
        }
        if primaryFD >= 0 {
            close(primaryFD)
            primaryFD = -1
        }
        continuation?.finish()
    }

    private func startReadSource() {
        let fd = primaryFD
        let queue = DispatchQueue(label: "maestro.shell-pty.read", qos: .utility)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let weakActor = WeakBox(self)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                read(fd, rawBuffer.baseAddress, rawBuffer.count)
            }
            if n > 0 {
                let data = Data(buffer.prefix(n))
                Task { await weakActor.value?.yieldOutput(data) }
            } else if n == 0 {
                Task { await weakActor.value?.handleEOF() }
            }
        }
        readSource = source
        source.resume()
    }

    private func yieldOutput(_ data: Data) {
        continuation?.yield(.output(data))
    }

    private func handleEOF() async {
        guard !terminated else { return }
        terminated = true
        if childPID > 0 {
            var status: Int32 = 0
            _ = waitpid(childPID, &status, 0)
            continuation?.yield(.exited(code: status))
        }
        if primaryFD >= 0 {
            close(primaryFD)
            primaryFD = -1
        }
        continuation?.finish()
    }
}

/// `WeakBox` — Swift 6 strict isolation 에서 Sendable closure capture 용. actor 의 weak ref 를
/// closure 에 그대로 캡처하면 race 경고가 남으므로 한 번 wrap.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T?) { self.value = value }
}

// TIOCSWINSZ = 0x80087467 on Darwin. C 매크로 직접 호출 불가 — 계산된 상수 사용.
private let tiocswinszRequest: UInt = 0x8008_7467
