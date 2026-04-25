@testable import MaestroCore
import XCTest

final class DarwinPTYShellSessionTests: XCTestCase {
    func testEchoProducesOutput() async throws {
        // /bin/echo 는 모든 macOS 에 있음 — CI 안전.
        let session = DarwinPTYShellSession(
            executablePath: "/bin/echo",
            arguments: ["hello-pty"]
        )
        try await session.start()
        let stream = await session.events
        var combined = Data()
        let deadline = Date().addingTimeInterval(3)
        loop: for await event in stream {
            switch event {
            case .output(let d):
                combined.append(d)
            case .exited:
                break loop
            case .error:
                XCTFail("error event")
                break loop
            }
            if Date() > deadline { break }
        }
        let text = String(decoding: combined, as: UTF8.self)
        XCTAssertTrue(text.contains("hello-pty"), "echo 출력에 인자가 포함되어야 함, got: \(text)")
        await session.terminate()
    }

    func testStartTwiceThrows() async throws {
        let session = DarwinPTYShellSession(
            executablePath: "/bin/echo",
            arguments: ["x"]
        )
        try await session.start()
        do {
            try await session.start()
            XCTFail("두 번째 start 는 throws 해야 함")
        } catch ShellSessionError.alreadyStarted {
            // ok
        }
        await session.terminate()
    }

    func testTerminateWithoutStartIsSafe() async {
        let session = DarwinPTYShellSession(
            executablePath: "/bin/echo",
            arguments: []
        )
        await session.terminate()
    }
}
