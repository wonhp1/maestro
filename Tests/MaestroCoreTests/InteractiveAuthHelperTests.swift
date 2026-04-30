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

    // MARK: - v0.10.0 Phase 2 — Task cancellation

    /// 외부 Task cancel → InteractiveAuthHelper 가 .cancelled 반환 + subprocess 정리.
    /// VendorPickerSheet 의 .onDisappear cancellation 흐름을 helper 단위로 검증.
    func testLoginCancelledByTaskCancellation() async throws {
        let tempHome = try makeEmptyHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let isolatedChecker = EnvironmentChecker(
            locator: EmptyLocator(),
            executor: NoopExec(),
            homeDirectory: tempHome,
            environment: [:]
        )
        // 자기 검증 — auth 가 false 임을 확인 (즉, polling 이 never success 트리거).
        let preflight = await isolatedChecker.checkCodexAuth()
        XCTAssertFalse(preflight.isReady, "테스트 격리 실패 — auth 가 이미 ready 면 cancel 검증 무의미")
        // /usr/bin/yes 는 무한히 출력 → polling 이 never 통과 → cancel 만이 종료 트리거.
        let yesBinary = URL(filePath: "/usr/bin/yes")
        let task = Task {
            await InteractiveAuthHelper.loginCodex(
                codexPath: yesBinary,
                checker: isolatedChecker,
                pollInterval: 0.05,
                timeout: 60  // 충분히 길게 — cancel 만이 중단 사유여야 함
            )
        }
        // 100ms 후 cancel
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, .cancelled, "외부 Task cancel 시 .cancelled 반환되어야 함")
    }

    // MARK: - v0.10.0 Phase 3 — generic spec API

    /// `OAuthCLISpec` + `login(spec:)` 으로 임의 CLI 인증 가능 — 미래 어댑터 추가 시 1줄.
    func testGenericSpecLoginInvalidPathFailsFast() async {
        let spec = InteractiveAuthHelper.OAuthCLISpec(
            executable: URL(filePath: "/nonexistent/whatever"),
            arguments: [],
            initialStdin: nil,
            authCheck: { false }
        )
        let result = await InteractiveAuthHelper.login(spec: spec, pollInterval: 0.05, timeout: 1)
        if case .processFailed = result { /* OK */ } else {
            XCTFail("expected processFailed for invalid path, got \(result)")
        }
    }

    /// v0.10.0 review must-fix: success 분기 happy path 커버리지 0% → spec 으로 검증.
    /// authCheck 가 true 반환하면 polling 루프가 `.success` 로 즉시 종료해야 함.
    func testGenericSpecLoginSuccessWhenAuthCheckPasses() async {
        let spec = InteractiveAuthHelper.OAuthCLISpec(
            executable: URL(filePath: "/usr/bin/yes"),  // 무한 출력 — 자체 종료 안 함
            arguments: [],
            initialStdin: nil,
            authCheck: { true }  // 첫 polling 즉시 success
        )
        let result = await InteractiveAuthHelper.login(spec: spec, pollInterval: 0.05, timeout: 5)
        XCTAssertEqual(result, .success, "authCheck=true 시 polling 즉시 success 종료")
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
