import Foundation

/// 외부 프로세스 실행을 추상화 — 테스트에서 모킹하기 위한 경계.
///
/// 구체 구현은 `DefaultProcessExecutor`. 테스트는 stub 으로 교체.
public protocol ProcessExecuting: Sendable {
    /// - Parameters:
    ///   - currentDirectoryURL: 자식 프로세스의 작업 디렉토리. `nil` 이면 호출 프로세스 cwd 상속.
    ///   - environment: 자식의 환경 변수. `nil` 이면 호출 프로세스 환경 상속.
    ///     **시크릿 누출 방지를 위해 어댑터는 `EnvironmentSanitizer.default.sanitizedProcessEnvironment()`
    ///     를 명시적으로 전달할 것** (Phase 6 권장).
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput
}

public extension ProcessExecuting {
    /// cwd / env 모두 호출 프로세스 상속 — 단순 케이스용.
    func run(executable: URL, arguments: [String]) async throws -> ProcessOutput {
        try await run(
            executable: executable,
            arguments: arguments,
            currentDirectoryURL: nil,
            environment: nil
        )
    }

    /// cwd 만 지정, env 는 상속 — 기존 호출자 호환.
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> ProcessOutput {
        try await run(
            executable: executable,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: nil
        )
    }
}

/// 프로세스 실행 결과. 비정상 exit 자체는 throws 가 아닌 `exitCode` 로 표현.
public struct ProcessOutput: Hashable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// 프로세스 실행 에러.
public enum ProcessExecutionError: Error, Equatable, Sendable {
    /// `Process.run()` 호출 자체가 실패 (실행 권한 없음, 잘못된 경로 등).
    case launchFailed(reason: String)
    /// 타임아웃 — 지정 시간 안에 종료되지 않아 SIGTERM/SIGKILL 으로 강제 종료.
    case timedOut
    /// 호출 측 Task 가 cancel 됨 — 자식 프로세스도 정리됨.
    case cancelled
}

/// `Foundation.Process` 기반 기본 구현.
///
/// 보장 사항:
/// - **동시 drain**: stdout/stderr 을 자식 실행 *중* 비동기로 읽어 pipe buffer (~16-64 KiB)
///   포화로 인한 deadlock 방지. (Phase 4 리뷰 must-fix)
/// - **출력 cap**: 각 스트림을 `maxOutputBytes` 까지만 보관, 초과분은 폐기 (자식의
///   write 는 계속 받음 → cap 후에도 deadlock 없음).
/// - **타임아웃 + SIGKILL 에스컬레이션**: `timeout` 초 내 미종료 시 SIGTERM →
///   `gracePeriod` 후에도 살아있으면 SIGKILL.
/// - **Task 취소 전파**: 호출 Task 가 cancel 되면 `withTaskCancellationHandler` 가
///   자식에 SIGTERM/SIGKILL.
/// - **FD 정리**: launch 실패 시 pipe 핸들 명시 close, 정상 종료 시 drain 함수 내 close.
public struct DefaultProcessExecutor: ProcessExecuting {
    public let timeout: TimeInterval
    public let gracePeriod: TimeInterval
    public let maxOutputBytes: Int

    public init(
        timeout: TimeInterval = 10,
        gracePeriod: TimeInterval = 1.5,
        maxOutputBytes: Int = 1 << 20
    ) {
        self.timeout = timeout
        self.gracePeriod = gracePeriod
        self.maxOutputBytes = maxOutputBytes
    }

    public func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let cwd = currentDirectoryURL {
            process.currentDirectoryURL = cwd
        }
        if let env = environment {
            process.environment = env
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exitNotifier = ExitNotifier()
        process.terminationHandler = { _ in exitNotifier.notify() }

        do {
            try process.run()
        } catch {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            throw ProcessExecutionError.launchFailed(reason: String(describing: error))
        }

        return try await withTaskCancellationHandler {
            try await runAfterLaunch(
                process: process,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                exitNotifier: exitNotifier
            )
        } onCancel: {
            Self.cancelChild(process: process, gracePeriod: gracePeriod)
        }
    }

    /// `process.run()` 이후의 drain + wait + 취소/타임아웃 처리. 함수 본문 길이 제한 분리.
    private func runAfterLaunch(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        exitNotifier: ExitNotifier
    ) async throws -> ProcessOutput {
        let cap = self.maxOutputBytes
        let timeoutSec = self.timeout
        let graceSec = self.gracePeriod
        do {
            async let stdoutTask = Self.drain(stdoutPipe.fileHandleForReading, cap: cap)
            async let stderrTask = Self.drain(stderrPipe.fileHandleForReading, cap: cap)
            let didExitInTime = await Self.waitWithTimeout(
                notifier: exitNotifier, timeout: timeoutSec
            )

            if !didExitInTime {
                process.terminate()
                let killed = await Self.waitWithTimeout(
                    notifier: exitNotifier, timeout: graceSec
                )
                if !killed {
                    kill(process.processIdentifier, SIGKILL)
                    await exitNotifier.wait()
                }
                _ = await stdoutTask
                _ = await stderrTask
                throw ProcessExecutionError.timedOut
            }

            let stdout = await stdoutTask
            let stderr = await stderrTask
            try Task.checkCancellation()
            return ProcessOutput(
                stdout: String(data: stdout, encoding: .utf8) ?? "",
                stderr: String(data: stderr, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus
            )
        } catch {
            await Self.ensureChildDead(process: process, gracePeriod: graceSec)
            throw error
        }
    }

    /// onCancel 에서 호출 — sync 컨텍스트. SIGTERM 후 비동기 SIGKILL 백업 예약.
    private static func cancelChild(process: Process, gracePeriod: TimeInterval) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + gracePeriod) {
            kill(pid, SIGKILL)
        }
    }

    /// 에러 경로에서 자식 정리. SIGTERM → grace → SIGKILL.
    private static func ensureChildDead(process: Process, gracePeriod: TimeInterval) async {
        guard process.isRunning else { return }
        process.terminate()
        try? await Task.sleep(nanoseconds: UInt64(gracePeriod * 1_000_000_000))
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// 핸들에서 EOF 까지 chunk 단위로 읽되 `cap` 바이트만 보관.
    /// 초과분도 계속 읽어 EOF 도달까지 진행 → 자식 write 차단 방지.
    private static func drain(_ handle: FileHandle, cap: Int) async -> Data {
        await Task.detached(priority: .userInitiated) {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                if buffer.count < cap {
                    let remaining = cap - buffer.count
                    buffer.append(chunk.prefix(remaining))
                }
            }
            try? handle.close()
            return buffer
        }.value
    }

    /// terminationHandler 가 알릴 때까지 대기, `timeout` 초 후 false 반환.
    /// 두 이벤트 (notify / timeout) 중 먼저 발생한 쪽으로 한 번만 resume — OneShot 패턴.
    private static func waitWithTimeout(
        notifier: ExitNotifier,
        timeout: TimeInterval
    ) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let resolver = OneShot(continuation: cont)
            notifier.onNotify { resolver.fire(true) }
            let nanos = UInt64(timeout * 1_000_000_000)
            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanos))) {
                resolver.fire(false)
            }
        }
    }
}

/// `CheckedContinuation` 을 한 번만 resume — 이미 resolve 된 경우 무시.
private final class OneShot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func fire(_ value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }
}

/// `Process.terminationHandler` 를 callback / async wait 양쪽으로 노출하는 일회성 게이트.
///
/// `notify()` 한 번 호출되면 이후 등록된 모든 콜백 즉시 실행, 이전 등록된 것도 실행. 멱등.
/// internal — `ProcessStreamer` 와 `ProcessExecuting` 모두 사용.
final class ExitNotifier: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var callbacks: [@Sendable () -> Void] = []

    func notify() {
        lock.lock()
        let toRun: [@Sendable () -> Void]
        if fired {
            toRun = []
        } else {
            fired = true
            toRun = callbacks
            callbacks.removeAll()
        }
        lock.unlock()
        for cb in toRun { cb() }
    }

    /// notify() 가 이미 호출됐으면 즉시 callback 실행. 아니면 나중에 한 번 실행.
    func onNotify(_ callback: @escaping @Sendable () -> Void) {
        lock.lock()
        if fired {
            lock.unlock()
            callback()
        } else {
            callbacks.append(callback)
            lock.unlock()
        }
    }

    /// notify() 를 async/await 으로 대기. (cancel 대응 없음 — cancel 시 leak 가능하므로
    /// 호출자가 직접 lifetime 관리.)
    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            onNotify { cont.resume() }
        }
    }
}
