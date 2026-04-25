@testable import MaestroCore
import XCTest

final class GlobalErrorHandlerTests: XCTestCase {
    override func tearDown() {
        // 다음 테스트 격리.
        GlobalErrorHandler.uninstall()
        super.tearDown()
    }

    func testInstallIsIdempotent() {
        // install 두 번 호출되어도 같은 핸들러가 설정되어 있는지 검증 (멱등).
        GlobalErrorHandler.install()
        let first = NSGetUncaughtExceptionHandler()
        GlobalErrorHandler.install()
        let second = NSGetUncaughtExceptionHandler()
        XCTAssertNotNil(first)
        XCTAssertEqual(unsafeBitCast(first, to: Int.self),
                       unsafeBitCast(second, to: Int.self))
    }

    func testUninstallRestoresPreviousHandler() {
        // 사전: 다른 sentinel 핸들러 설치 → install → uninstall 후 sentinel 복귀.
        let sentinel: @convention(c) (NSException) -> Void = { _ in }
        NSSetUncaughtExceptionHandler(sentinel)
        let before = NSGetUncaughtExceptionHandler()

        GlobalErrorHandler.install()
        let installed = NSGetUncaughtExceptionHandler()
        XCTAssertNotEqual(unsafeBitCast(before, to: Int.self),
                          unsafeBitCast(installed, to: Int.self))

        GlobalErrorHandler.uninstall()
        let after = NSGetUncaughtExceptionHandler()
        XCTAssertEqual(unsafeBitCast(before, to: Int.self),
                       unsafeBitCast(after, to: Int.self))

        // cleanup
        NSSetUncaughtExceptionHandler(nil)
    }

    func testLogErrorDoesNotThrow() {
        struct TestError: Error, CustomStringConvertible {
            let description: String = "test failure"
        }
        // 단순 호출이 throws / crash 하지 않는지 확인. OSLog 출력은 sample 가능 영역 밖.
        GlobalErrorHandler.log(TestError())
        GlobalErrorHandler.log(TestError(), category: .adapter)
        GlobalErrorHandler.log(TestError(), category: .persistence)
    }
}
