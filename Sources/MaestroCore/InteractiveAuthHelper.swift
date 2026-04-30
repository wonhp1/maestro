import AppKit
import Foundation

/// v0.10.0 — 인앱 OAuth 로그인 도우미.
///
/// 두 CLI 의 행동이 다름:
/// - **Codex**: `codex login` 이 stdout 에 OAuth URL 출력 + 자체 브라우저 오픈 시도.
///   파이프 캡처 시 자체 오픈이 실패할 수 있어 Maestro 가 URL 추출해서
///   `NSWorkspace.shared.open(url)` 백업.
/// - **Gemini**: `gemini -p` 가 URL 안 찍고 interactive prompt
///   `Do you want to continue? [Y/n]:` 띄움. stdin 으로 `Y\n` 보내야
///   Gemini 가 직접 브라우저 오픈.
///
/// v0.10.0 Phase 3: `OAuthCLISpec` 으로 N-CLI 일반화 + `runOAuthSubprocess` 를
/// 3개 stage (setup / writeStdin / poll) 로 분리. lint disable 제거.
public enum InteractiveAuthHelper {
    public enum LoginResult: Sendable, Equatable {
        case success
        case cancelled
        case timedOut
        case processFailed(message: String)
        /// v0.9.8: 브라우저 자동 오픈 실패 — 사용자가 수동으로 URL 방문 필요.
        case browserOpenFailed(url: URL)
    }

    /// v0.10.0 — N-CLI 일반화: 새 OAuth CLI 추가 시 spec 만 만들면 된다.
    public struct OAuthCLISpec: Sendable {
        public let executable: URL
        public let arguments: [String]
        public let initialStdin: String?
        public let authCheck: @Sendable () async -> Bool

        public init(
            executable: URL,
            arguments: [String],
            initialStdin: String?,
            authCheck: @escaping @Sendable () async -> Bool
        ) {
            self.executable = executable
            self.arguments = arguments
            self.initialStdin = initialStdin
            self.authCheck = authCheck
        }
    }

    /// 매직 상수.
    private static let urlPattern = #"https://[^\s)]+"#
    private static let errorTailLength = 200
    private static let oauthHostHints = ["oauth", "accounts.google.com", "auth.openai.com"]

    // MARK: - Public entry points

    /// `codex login` spawn → URL 추출 + 브라우저 오픈 → polling.
    public static func loginCodex(
        codexPath: URL,
        checker: EnvironmentChecker = EnvironmentChecker(),
        pollInterval: TimeInterval = 2,
        timeout: TimeInterval = 300
    ) async -> LoginResult {
        await login(
            spec: OAuthCLISpec(
                executable: codexPath,
                arguments: ["login"],
                initialStdin: nil,
                authCheck: { await checker.checkCodexAuth().isReady }
            ),
            pollInterval: pollInterval,
            timeout: timeout
        )
    }

    /// `gemini -p "ping" --yolo --skip-trust` spawn → stdin 에 Y\n → Gemini 가 브라우저 오픈 → polling.
    /// Gemini 는 별도 login 명령 없음 — 첫 prompt 호출 시 OAuth interactive prompt 트리거.
    public static func loginGemini(
        geminiPath: URL,
        checker: EnvironmentChecker = EnvironmentChecker(),
        pollInterval: TimeInterval = 2,
        timeout: TimeInterval = 300
    ) async -> LoginResult {
        await login(
            spec: OAuthCLISpec(
                executable: geminiPath,
                arguments: ["-p", "ping", "--yolo", "--skip-trust"],
                initialStdin: "Y\n",
                authCheck: { await checker.checkGeminiAuth().isReady }
            ),
            pollInterval: pollInterval,
            timeout: timeout
        )
    }

    /// v0.10.0 — generic spec 기반 entry point. 미래 CLI (Cursor / Aider OAuth 등)
    /// 추가 시 spec 만 만들어서 호출.
    public static func login(
        spec: OAuthCLISpec,
        pollInterval: TimeInterval = 2,
        timeout: TimeInterval = 300
    ) async -> LoginResult {
        let setup: OAuthSetup
        do {
            setup = try setupOAuthProcess(spec: spec)
        } catch {
            return .processFailed(message: "실행 실패: \(error.localizedDescription)")
        }
        defer { setup.cleanupHandlers() }
        injectInitialStdin(spec.initialStdin, into: setup.inputPipe)
        return await pollForCompletion(
            setup: setup,
            authCheck: spec.authCheck,
            pollInterval: pollInterval,
            timeout: timeout
        )
    }

    // MARK: - Stage 1: setup

    /// v0.10.0 — 동기 단일 task 내부 전달 전용. `Process`/`Pipe` 가 non-Sendable 이므로
    /// 의도적으로 `Sendable` 채택 안 함 — Task 경계 너머로 보내려고 하면 컴파일 에러로 차단.
    /// `cleanupHandlers` 도 같은 이유로 `@Sendable` 안 붙임 (defer-only 사용).
    private struct OAuthSetup {
        let process: Process
        let accumulator: OutputAccumulator
        let inputPipe: Pipe?
        let cleanupHandlers: () -> Void
    }

    private static func setupOAuthProcess(spec: OAuthCLISpec) throws -> OAuthSetup {
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let inputPipe: Pipe? = spec.initialStdin != nil ? Pipe() : nil
        if let inputPipe { process.standardInput = inputPipe }

        let accumulator = OutputAccumulator()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                accumulator.append(text)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                accumulator.append(text)
            }
        }
        let cleanup = {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
        } catch {
            cleanup()
            throw error
        }
        return OAuthSetup(
            process: process,
            accumulator: accumulator,
            inputPipe: inputPipe,
            cleanupHandlers: cleanup
        )
    }

    // MARK: - Stage 2: stdin 주입 (Gemini 의 [Y/n] prompt 응답)

    private static func injectInitialStdin(_ payload: String?, into pipe: Pipe?) {
        guard let pipe, let bytes = payload?.data(using: .utf8) else { return }
        try? pipe.fileHandleForWriting.write(contentsOf: bytes)
        try? pipe.fileHandleForWriting.close()
    }

    // MARK: - Stage 3: polling 루프

    private static func pollForCompletion(
        setup: OAuthSetup,
        authCheck: @escaping @Sendable () async -> Bool,
        pollInterval: TimeInterval,
        timeout: TimeInterval
    ) async -> LoginResult {
        var openedURL = false
        let deadline = Date().addingTimeInterval(timeout)
        let pollNanos = UInt64(pollInterval * 1_000_000_000)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: pollNanos)
            } catch {
                terminateIfRunning(setup.process)
                return .cancelled
            }
            if Task.isCancelled {
                terminateIfRunning(setup.process)
                return .cancelled
            }
            if !openedURL,
               let url = Self.extractOAuthURL(from: setup.accumulator.snapshot()) {
                let opened = await MainActor.run { NSWorkspace.shared.open(url) }
                openedURL = true
                if !opened {
                    terminateIfRunning(setup.process)
                    return .browserOpenFailed(url: url)
                }
            }
            if await authCheck() {
                terminateIfRunning(setup.process)
                return .success
            }
            if let result = checkProcessExited(setup) {
                return result
            }
        }
        terminateIfRunning(setup.process)
        return .timedOut
    }

    /// 프로세스가 종료됐다면 그 결과를 LoginResult 로 변환. 아직 살아있으면 nil.
    private static func checkProcessExited(_ setup: OAuthSetup) -> LoginResult? {
        guard !setup.process.isRunning else { return nil }
        let exitCode = setup.process.terminationStatus
        if exitCode == 0 { return .cancelled }
        let snapshot = setup.accumulator.snapshot()
        let cliName = setup.process.executableURL?.lastPathComponent ?? "process"
        return .processFailed(
            message: "\(cliName) exit \(exitCode): \(snapshot.suffix(errorTailLength))"
        )
    }

    // MARK: - URL 추출

    /// stdout/stderr 에서 첫 OAuth URL 추출.
    /// Codex: `https://auth.openai.com/oauth/authorize?...`
    /// Gemini: URL 안 찍어서 사용 안 함 (Gemini 가 직접 브라우저 오픈).
    static func extractOAuthURL(from text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var fallback: String?
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let candidate = String(text[r])
            if oauthHostHints.contains(where: candidate.contains) {
                return URL(string: candidate)
            }
            if fallback == nil { fallback = candidate }
        }
        return fallback.flatMap(URL.init(string:))
    }

    private static func terminateIfRunning(_ process: Process) {
        if process.isRunning {
            process.terminate()
        }
    }
}

/// stdout/stderr 누적기 — readabilityHandler 가 background queue 에서 호출 → lock 필수.
private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        text += s
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return text
    }
}
