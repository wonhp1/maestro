@testable import MaestroCore
import XCTest

final class InteractiveAuthHelperTests: XCTestCase {
    func testLoginResultEquatable() {
        XCTAssertEqual(InteractiveAuthHelper.LoginResult.success, .success)
        XCTAssertEqual(InteractiveAuthHelper.LoginResult.cancelled, .cancelled)
        XCTAssertEqual(InteractiveAuthHelper.LoginResult.timedOut, .timedOut)
        XCTAssertNotEqual(
            InteractiveAuthHelper.LoginResult.success,
            .processFailed(message: "x")
        )
    }

    /// 짧은 timeout + 존재하지 않는 path → processFailed 빠르게 반환.
    func testLoginCodexInvalidPathFailsFast() async {
        let invalid = URL(filePath: "/nonexistent/codex-fake")
        let result = await InteractiveAuthHelper.loginCodex(
            codexPath: invalid,
            pollInterval: 0.05,
            timeout: 1
        )
        if case .processFailed = result { /* OK */ } else {
            XCTFail("expected processFailed, got \(result)")
        }
    }

    /// 짧은 timeout + 어차피 auth 안 되는 stub path → timedOut 반환.
    /// (실 codex 호출 안 함 — `/usr/bin/true` 가 즉시 종료, polling 이 not-auth 라
    /// timedOut 또는 cancelled 둘 다 가능 — 결과 보고 OK 처리)
    func testLoginCodexShortTimeoutReturnsResult() async {
        // /bin/true 는 즉시 exit 0 → process 빨리 종료 → polling 이 cancelled 반환.
        let trueBinary = URL(filePath: "/usr/bin/true")
        let result = await InteractiveAuthHelper.loginCodex(
            codexPath: trueBinary,
            pollInterval: 0.05,
            timeout: 0.3
        )
        // 어떤 결과든 nil 아니어야 함 (success 는 절대 X — 인증 안 됨).
        XCTAssertNotEqual(result, .success)
    }
}
