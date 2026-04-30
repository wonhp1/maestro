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
    func testLoginCodexShortTimeoutReturnsResult() async throws {
        // 실제 ~/.codex/auth.json 영향 차단 — empty home 으로 격리.
        let tempHome = try makeEmptyHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let isolatedChecker = EnvironmentChecker(
            locator: EmptyLocator(),
            executor: NoopExec(),
            homeDirectory: tempHome,
            environment: [:]
        )
        let trueBinary = URL(filePath: "/usr/bin/true")
        let result = await InteractiveAuthHelper.loginCodex(
            codexPath: trueBinary,
            checker: isolatedChecker,
            pollInterval: 0.05,
            timeout: 0.3
        )
        XCTAssertNotEqual(result, .success)
    }

    func testLoginGeminiInvalidPathFailsFast() async {
        let invalid = URL(filePath: "/nonexistent/gemini-fake")
        let result = await InteractiveAuthHelper.loginGemini(
            geminiPath: invalid,
            pollInterval: 0.05,
            timeout: 1
        )
        if case .processFailed = result { /* OK */ } else {
            XCTFail("expected processFailed, got \(result)")
        }
    }

    func testLoginGeminiShortTimeoutReturnsResult() async throws {
        let tempHome = try makeEmptyHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let isolatedChecker = EnvironmentChecker(
            locator: EmptyLocator(),
            executor: NoopExec(),
            homeDirectory: tempHome,
            environment: [:]
        )
        let trueBinary = URL(filePath: "/usr/bin/true")
        let result = await InteractiveAuthHelper.loginGemini(
            geminiPath: trueBinary,
            checker: isolatedChecker,
            pollInterval: 0.05,
            timeout: 0.3
        )
        XCTAssertNotEqual(result, .success)
    }

    // MARK: - extractOAuthURL

    func testExtractOAuthURLPrefersGoogleOAuth() {
        let text = """
            Some intro text.
            Open this URL: https://accounts.google.com/o/oauth2/auth?client_id=abc&scope=...
            Done.
            """
        let url = InteractiveAuthHelper.extractOAuthURL(from: text)
        XCTAssertEqual(url?.host, "accounts.google.com")
    }

    func testExtractOAuthURLPrefersOpenAIOAuth() {
        let text = "Visit https://auth.openai.com/oauth/authorize?response_type=code to log in."
        let url = InteractiveAuthHelper.extractOAuthURL(from: text)
        XCTAssertEqual(url?.host, "auth.openai.com")
    }

    func testExtractOAuthURLFallsBackToFirstHTTPS() {
        let text = "See https://example.com/info for details."
        let url = InteractiveAuthHelper.extractOAuthURL(from: text)
        XCTAssertEqual(url?.host, "example.com")
    }

    func testExtractOAuthURLReturnsNilForNoURL() {
        XCTAssertNil(InteractiveAuthHelper.extractOAuthURL(from: "no urls here"))
    }

    func testExtractOAuthURLPrefersOAuthOverPlainHTTPS() {
        // 첫 https 가 OAuth 가 아니면 뒤에 나오는 OAuth URL 을 우선해야 함.
        let text = """
            Logo: https://cdn.example.com/logo.png
            Login: https://accounts.google.com/o/oauth2/v2/auth?...
            """
        let url = InteractiveAuthHelper.extractOAuthURL(from: text)
        XCTAssertEqual(url?.host, "accounts.google.com")
    }

    // MARK: - Helpers

    private func makeEmptyHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-auth-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private struct EmptyLocator: ExecutableLocating {
    func locate(_ name: String) -> URL? { nil }
}

private struct NoopExec: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        ProcessOutput(stdout: "", stderr: "", exitCode: 1)
    }
}
