import Foundation

/// 프로세스 stdout/stderr 의 **라인 단위 스트리밍 이벤트**.
///
/// `DefaultProcessStreamer.stream(...)` 가 발행. 마지막 이벤트는 항상 `.exited`,
/// 이후 stream 이 finish.
public struct ProcessStreamEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// stdout 의 한 줄 (개행 미포함, trailing `\r` 제거 — CRLF 대응).
        case stdoutLine(String)
        /// stderr 의 한 줄 (개행 미포함, trailing `\r` 제거).
        case stderrLine(String)
        /// 프로세스 종료. 정상 exit / signal 구분.
        case exited(exitCode: Int32, reason: TerminationReason)
    }

    /// 종료 원인 — `Process.terminationReason` 의 추상화.
    public enum TerminationReason: Hashable, Sendable {
        case exit
        case uncaughtSignal(Int32)
    }

    public let kind: Kind
    public let timestamp: Date

    public init(kind: Kind, timestamp: Date = Date()) {
        self.kind = kind
        self.timestamp = timestamp
    }
}

/// 외부 프로세스를 spawn 하여 출력을 **라인 단위로 실시간 스트리밍**하는 추상화.
public protocol ProcessStreaming: Sendable {
    func stream(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessStreamEvent, Error>
}

/// `Foundation.Process` + Task-based 동시 drain 기반 구현.
///
/// 보장:
/// - **race-free 라인 분할**: drain Task 가 EOF 까지 직접 read → readabilityHandler/
///   terminationHandler 사이의 race 없음. 모든 라인 보존.
/// - **메모리 cap**: 단일 라인이 `maxLineBytes` 초과 시 잘라서 emit, 잔여는 다음 \n 까지 skip.
/// - **CRLF**: trailing `\r` 자동 제거.
/// - **타임아웃**: SIGTERM → grace → SIGKILL. timeout 시 stream 은 `ProcessExecutionError.timedOut` 으로 finish.
/// - **Task 취소**: 소비자 break / 외부 cancel 시 자식 SIGTERM/SIGKILL.
/// - **PID reuse 방어**: SIGKILL 직전 `process.isRunning` 재확인.
/// - **launch 실패**: `ProcessExecutionError.launchFailed`.
public struct DefaultProcessStreamer: ProcessStreaming {
    public let timeout: TimeInterval?
    public let gracePeriod: TimeInterval
    public let maxLineBytes: Int

    public init(
        timeout: TimeInterval? = nil,
        gracePeriod: TimeInterval = 1.5,
        maxLineBytes: Int = 1 << 20
    ) {
        self.timeout = timeout
        self.gracePeriod = gracePeriod
        self.maxLineBytes = maxLineBytes
    }

    public func stream(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<ProcessStreamEvent, Error> {
        let ctx = StreamContext(
            executable: executable,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            timeoutSec: timeout,
            graceSec: gracePeriod,
            maxLineBytes: maxLineBytes
        )
        return AsyncThrowingStream { continuation in
            let driver = Task.detached(priority: .userInitiated) {
                guard ctx.start(continuation: continuation) else { return }
                await ctx.runUntilFinished(continuation: continuation)
                ctx.finish(continuation: continuation)
            }
            continuation.onTermination = { _ in driver.cancel() }
        }
    }
}

/// `drive` 의 상태 + 단계별 메서드 — 함수 길이/파라미터 수 분리.
private final class StreamContext: @unchecked Sendable {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdoutBuffer: LineBuffer
    let stderrBuffer: LineBuffer
    let exitNotifier = ExitNotifier()
    let timeoutFlag = AtomicFlag()
    let timeoutSec: TimeInterval?
    let graceSec: TimeInterval

    init(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?,
        timeoutSec: TimeInterval?,
        graceSec: TimeInterval,
        maxLineBytes: Int
    ) {
        self.timeoutSec = timeoutSec
        self.graceSec = graceSec
        self.stdoutBuffer = LineBuffer(maxLineBytes: maxLineBytes)
        self.stderrBuffer = LineBuffer(maxLineBytes: maxLineBytes)
        process.executableURL = executable
        process.arguments = arguments
        if let cwd = currentDirectoryURL { process.currentDirectoryURL = cwd }
        if let env = environment { process.environment = env }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let notifier = exitNotifier
        process.terminationHandler = { _ in notifier.notify() }
    }

    func start(
        continuation: AsyncThrowingStream<ProcessStreamEvent, Error>.Continuation
    ) -> Bool {
        do {
            try process.run()
            return true
        } catch {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            continuation.finish(
                throwing: ProcessExecutionError.launchFailed(reason: String(describing: error))
            )
            return false
        }
    }

    func runUntilFinished(
        continuation: AsyncThrowingStream<ProcessStreamEvent, Error>.Continuation
    ) async {
        let outTask = Task.detached(priority: .userInitiated) { [self] in
            await drain(stdoutPipe.fileHandleForReading, into: stdoutBuffer,
                        stdout: true, continuation: continuation)
        }
        let errTask = Task.detached(priority: .userInitiated) { [self] in
            await drain(stderrPipe.fileHandleForReading, into: stderrBuffer,
                        stdout: false, continuation: continuation)
        }
        let watchdog = startWatchdog()
        await withTaskCancellationHandler {
            await outTask.value
            await errTask.value
            await exitNotifier.wait()
        } onCancel: { [weak self] in
            self?.terminateChild()
        }
        watchdog?.cancel()
    }

    func finish(
        continuation: AsyncThrowingStream<ProcessStreamEvent, Error>.Continuation
    ) {
        if let r = stdoutBuffer.flushRemaining() {
            continuation.yield(ProcessStreamEvent(kind: .stdoutLine(r)))
        }
        if let r = stderrBuffer.flushRemaining() {
            continuation.yield(ProcessStreamEvent(kind: .stderrLine(r)))
        }
        if timeoutFlag.get() {
            continuation.finish(throwing: ProcessExecutionError.timedOut)
            return
        }
        let reason: ProcessStreamEvent.TerminationReason
        switch process.terminationReason {
        case .exit: reason = .exit
        case .uncaughtSignal: reason = .uncaughtSignal(process.terminationStatus)
        @unknown default: reason = .exit
        }
        continuation.yield(
            ProcessStreamEvent(
                kind: .exited(exitCode: process.terminationStatus, reason: reason)
            )
        )
        continuation.finish()
    }

    private func startWatchdog() -> Task<Void, Never>? {
        guard let secs = timeoutSec else { return nil }
        let grace = graceSec
        return Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
            guard let self, self.process.isRunning else { return }
            self.timeoutFlag.set()
            self.process.terminate()
            try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
            if self.process.isRunning {
                kill(self.process.processIdentifier, SIGKILL)
            }
        }
    }

    private func terminateChild() {
        guard process.isRunning else { return }
        process.terminate()
        let proc = process
        let grace = graceSec
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak proc] in
            guard let p = proc, p.isRunning else { return }
            kill(p.processIdentifier, SIGKILL)
        }
    }
}

/// 파이프에서 EOF 까지 byte chunk 읽어 LineBuffer 통과 후 라인 별 yield.
/// `availableData` 가 빈 Data 를 반환하면 EOF — 종료.
private func drain(
    _ handle: FileHandle,
    into buffer: LineBuffer,
    stdout: Bool,
    continuation: AsyncThrowingStream<ProcessStreamEvent, Error>.Continuation
) async {
    while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        for line in buffer.append(chunk) {
            let event = stdout
                ? ProcessStreamEvent(kind: .stdoutLine(line))
                : ProcessStreamEvent(kind: .stderrLine(line))
            continuation.yield(event)
        }
    }
    try? handle.close()
}

// MARK: - Internal helpers

/// 들어오는 byte chunks 를 `\n` 기준으로 라인 분할. 부분 라인은 보류.
/// CRLF 자동 제거. cap 초과 시 잘라서 emit, 다음 chunk 까지 skip 모드.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var skippingToNextNewline = false  // cap 초과 라인의 잔여 skip
    private let maxLineBytes: Int

    init(maxLineBytes: Int) {
        self.maxLineBytes = maxLineBytes
    }

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while true {
            if skippingToNextNewline {
                if let nl = pending.firstIndex(of: 0x0A) {
                    pending = Data(pending.suffix(from: pending.index(after: nl)))
                    skippingToNextNewline = false
                    continue
                } else {
                    pending.removeAll()
                    break
                }
            }
            // Cap: 만약 첫 maxLineBytes 안에 \n 이 없으면 → cap 초과 라인 시작.
            if pending.count >= maxLineBytes {
                let head = pending.prefix(maxLineBytes)
                if !head.contains(0x0A) {
                    lines.append(decode(head))
                    pending = Data(
                        pending.suffix(from: pending.index(pending.startIndex, offsetBy: maxLineBytes))
                    )
                    skippingToNextNewline = true
                    continue
                }
            }
            guard let nl = pending.firstIndex(of: 0x0A) else { break }
            let line = pending.prefix(upTo: nl)
            lines.append(decode(line))
            pending = Data(pending.suffix(from: pending.index(after: nl)))
        }
        return lines
    }

    func flushRemaining() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty, !skippingToNextNewline else {
            pending.removeAll()
            return nil
        }
        let str = decode(pending)
        pending.removeAll()
        return str
    }

    /// trailing `\r` 제거 + UTF-8 디코드.
    private func decode(_ data: Data) -> String {
        var slice = data
        if let last = slice.last, last == 0x0D {
            slice = slice.dropLast()
        }
        return String(decoding: slice, as: UTF8.self)
    }
}

// `ExitNotifier` 정의는 `ProcessExecuting.swift` 에 있는 것을 공유.

/// 1회만 set, multiple read — timeout 신호용.
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
