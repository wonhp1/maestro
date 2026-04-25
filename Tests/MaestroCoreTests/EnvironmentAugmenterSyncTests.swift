@testable import MaestroCore
import XCTest

final class EnvironmentAugmenterSyncTests: XCTestCase {
    private var savedPATH: String?

    override func setUp() {
        super.setUp()
        savedPATH = ProcessInfo.processInfo.environment["PATH"]
        EnvironmentAugmenter.resetForTesting()
    }

    override func tearDown() {
        if let saved = savedPATH {
            saved.withCString { _ = setenv("PATH", $0, 1) }
        }
        EnvironmentAugmenter.resetForTesting()
        super.tearDown()
    }

    func testSyncAugmentSucceedsAgainstRealShell() {
        let result = EnvironmentAugmenter.augmentPATHFromLoginShellSync(timeout: 3.0)
        guard case .augmented = result else {
            XCTFail("expected .augmented, got \(result)")
            return
        }
        // 머지 후 PATH 가 비지 않음
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        XCTAssertFalse(pathEnv.isEmpty)
    }

    func testSyncIsIdempotent() {
        _ = EnvironmentAugmenter.augmentPATHFromLoginShellSync(timeout: 3.0)
        let second = EnvironmentAugmenter.augmentPATHFromLoginShellSync(timeout: 3.0)
        guard case .alreadyAugmented = second else {
            XCTFail("second call must be alreadyAugmented")
            return
        }
    }

    func testSyncTimeoutWithBogusShell() {
        // /usr/bin/yes 는 무한 출력 — timeout trigger.
        let result = EnvironmentAugmenter.augmentPATHFromLoginShellSync(
            shellURL: URL(fileURLWithPath: "/usr/bin/yes"),
            timeout: 0.3
        )
        guard case .extractFailed(let error) = result,
              case LoginShellPathExtractorError.timedOut = error else {
            XCTFail("expected .extractFailed(.timedOut), got \(result)")
            return
        }
    }
}
