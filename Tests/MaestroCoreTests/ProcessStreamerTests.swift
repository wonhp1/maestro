import Foundation
@testable import MaestroCore
import XCTest

final class ProcessStreamerTests: XCTestCase {
    func testEchoYieldsStdoutLineThenExited() async throws {
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello world"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var events: [ProcessStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        XCTAssertGreaterThanOrEqual(events.count, 2)
        if case .stdoutLine(let text) = events[0].kind {
            XCTAssertEqual(text, "hello world")
        } else {
            XCTFail("first event not stdoutLine: \(events[0])")
        }
        if case .exited(let code, let reason) = events.last?.kind {
            XCTAssertEqual(code, 0)
            XCTAssertEqual(reason, .exit)
        } else {
            XCTFail("last event not exited: \(String(describing: events.last))")
        }
    }

    func testStderrLineSeparatedFromStdout() async throws {
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo on-out; echo on-err 1>&2"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var stdoutLines: [String] = []
        var stderrLines: [String] = []
        var exitCode: Int32 = -1
        for try await event in stream {
            switch event.kind {
            case .stdoutLine(let s): stdoutLines.append(s)
            case .stderrLine(let s): stderrLines.append(s)
            case .exited(let code, _): exitCode = code
            }
        }
        XCTAssertEqual(stdoutLines, ["on-out"])
        XCTAssertEqual(stderrLines, ["on-err"])
        XCTAssertEqual(exitCode, 0)
    }

    func testMultipleLinesYieldedSeparately() async throws {
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'a\\nb\\nc\\n'"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var lines: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { lines.append(s) }
        }
        XCTAssertEqual(lines, ["a", "b", "c"])
    }

    func testPartialLineAtEOFEmittedOnExit() async throws {
        // 마지막 newline 없이 종료 — flushRemaining 이 그 partial 을 emit 해야 함.
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'no-newline-end'"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var lines: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { lines.append(s) }
        }
        XCTAssertEqual(lines, ["no-newline-end"])
    }

    func testLaunchFailureSurfacedAsError() async {
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/no/such/binary/zzz"),
            arguments: [],
            currentDirectoryURL: nil,
            environment: nil
        )
        do {
            for try await _ in stream {}
            XCTFail("expected launchFailed")
        } catch ProcessExecutionError.launchFailed {
            // OK
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testTimeoutTerminatesAndStreamThrows() async throws {
        let streamer = DefaultProcessStreamer(timeout: 0.3, gracePeriod: 0.5)
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            currentDirectoryURL: nil,
            environment: nil
        )
        let start = Date()
        do {
            for try await _ in stream {}
            XCTFail("expected timedOut")
        } catch ProcessExecutionError.timedOut {
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, 2.0, "timeout enforcement too slow: \(elapsed)s")
        } catch {
            XCTFail("expected timedOut, got \(error)")
        }
    }

    func testCancellationKillsChildPromptly() async throws {
        let streamer = DefaultProcessStreamer(timeout: 30)
        let task = Task {
            let stream = streamer.stream(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                currentDirectoryURL: nil,
                environment: nil
            )
            for try await _ in stream {}
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        let start = Date()
        task.cancel()
        _ = try? await task.value
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5.0, "child not killed quickly: \(elapsed)s")
    }

    func testCustomEnvironmentApplied() async throws {
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $MAESTRO_TEST_VAR"],
            currentDirectoryURL: nil,
            environment: ["MAESTRO_TEST_VAR": "applied", "PATH": "/bin:/usr/bin"]
        )
        var lines: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { lines.append(s) }
        }
        XCTAssertEqual(lines, ["applied"])
    }

    func testSanitizedEnvironmentDropsSecret() async throws {
        // 부모 env 에 가짜 토큰 set → sanitize 후 자식에 노출 안 됨.
        setenv("ANTHROPIC_API_KEY", "fake-secret", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        let cleaned = EnvironmentSanitizer.default.sanitizedProcessEnvironment()
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo \"key=${ANTHROPIC_API_KEY:-MISSING}\""],
            currentDirectoryURL: nil,
            environment: cleaned
        )
        var lines: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { lines.append(s) }
        }
        XCTAssertEqual(lines, ["key=MISSING"], "secret leaked: \(lines)")
    }

    /// Phase 6 must-fix: 대량 라인 스트리밍 시 모든 라인이 순서 보존하여 emit.
    func testHighVolumeStreamPreservesOrderAndCount() async throws {
        let lineCount = 5000
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/usr/bin/seq"),
            arguments: ["1", "\(lineCount)"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var received: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { received.append(s) }
        }
        XCTAssertEqual(received.count, lineCount, "받은 라인 수 부족: \(received.count)")
        guard received.count == lineCount else { return }
        XCTAssertEqual(received.first, "1")
        XCTAssertEqual(received.last, "\(lineCount)")
        XCTAssertEqual(received[2499], "2500")
    }

    /// Phase 6 must-fix: multi-byte UTF-8 (한글) 가 chunk 경계에 잘려도 라인 복원 정확.
    func testMultibyteUTF8AcrossReadsPreserved() async throws {
        // 한 라인을 100KB+ 로 만들어 read 경계 강제.
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "for i in $(seq 1 1000); do printf '한글테스트'; done; printf '\\n'"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var lines: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { lines.append(s) }
        }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.count, "한글테스트".count * 1000)
    }

    /// CRLF 종료 라인의 trailing \r 제거.
    func testCRLFTrailingCarriageReturnStripped() async throws {
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'abc\\r\\n'"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var lines: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { lines.append(s) }
        }
        XCTAssertEqual(lines, ["abc"])
    }

    /// Phase 6 must-fix: 출력 없는 프로세스는 .exited 만 emit.
    func testZeroOutputProcessYieldsOnlyExited() async throws {
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            currentDirectoryURL: nil,
            environment: nil
        )
        var events: [ProcessStreamEvent] = []
        for try await event in stream { events.append(event) }
        XCTAssertEqual(events.count, 1)
        if case .exited(let code, let reason) = events[0].kind {
            XCTAssertEqual(code, 0)
            XCTAssertEqual(reason, .exit)
        } else {
            XCTFail("expected single exited event")
        }
    }

    /// Phase 6 must-fix: signal 종료 (kill -9) 는 reason=.uncaughtSignal.
    func testSignalKilledProcessReportsUncaughtSignal() async throws {
        let streamer = DefaultProcessStreamer()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "kill -9 $$"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var lastReason: ProcessStreamEvent.TerminationReason?
        for try await event in stream {
            if case .exited(_, let reason) = event.kind { lastReason = reason }
        }
        if case .uncaughtSignal = lastReason { /* OK */ } else {
            XCTFail("expected uncaughtSignal, got \(String(describing: lastReason))")
        }
    }

    /// 메모리 cap — 한 라인이 maxLineBytes 넘으면 잘려서 emit, 잔여 폐기.
    func testLineCapTruncatesOversizedLines() async throws {
        let streamer = DefaultProcessStreamer(maxLineBytes: 100)
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 5000 /dev/zero | tr '\\0' 'X'; echo; echo done"],
            currentDirectoryURL: nil,
            environment: nil
        )
        var lines: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { lines.append(s) }
        }
        XCTAssertEqual(lines.count, 2)
        XCTAssertLessThanOrEqual(lines[0].utf8.count, 100)
        XCTAssertEqual(lines[1], "done")
    }

    func testCwdPropagatedToChild() async throws {
        let streamer = DefaultProcessStreamer()
        let cwd = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let stream = streamer.stream(
            executable: URL(fileURLWithPath: "/bin/pwd"),
            arguments: [],
            currentDirectoryURL: cwd,
            environment: nil
        )
        var lines: [String] = []
        for try await event in stream {
            if case .stdoutLine(let s) = event.kind { lines.append(s) }
        }
        XCTAssertEqual(lines.count, 1)
        let pwd = lines.first ?? ""
        // macOS 가 /var/folders 를 /private/var/folders 로 canonicalize — 양쪽 normalize 후 비교.
        let pwdResolved = URL(fileURLWithPath: pwd).resolvingSymlinksInPath().path
        XCTAssertEqual(pwdResolved, cwd.path)
    }
}
