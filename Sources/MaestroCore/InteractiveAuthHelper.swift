import AppKit
import Foundation

/// v0.9.5 — 인앱 OAuth 로그인 도우미.
///
/// 두 CLI 의 행동이 다름:
/// - **Codex**: `codex login` 이 stdout 에 OAuth URL 출력 + 자체 브라우저 오픈 시도.
///   파이프 캡처 시 자체 오픈이 실패할 수 있어 Maestro 가 URL 추출해서
///   `NSWorkspace.shared.open(url)` 백업.
/// - **Gemini**: `gemini -p` 가 URL 안 찍고 interactive prompt
///   `Do you want to continue? [Y/n]:` 띄움. stdin 으로 `Y\n` 보내야
///   Gemini 가 직접 브라우저 오픈.
///
/// 사용자 경험:
/// 1. Maestro 의 "로그인" 버튼 클릭
/// 2. 브라우저 자동 열림
/// 3. 로그인 후 Maestro 가 polling 해서 자동 갱신
public enum InteractiveAuthHelper {
    public enum LoginResult: Sendable, Equatable {
        case success
        case cancelled
        case timedOut
        case processFailed(message: String)
        /// v0.9.8: 브라우저 자동 오픈 실패 — 사용자가 수동으로 URL 방문 필요.
        case browserOpenFailed(url: URL)
    }

    /// 매직 상수.
    private static let urlPattern = #"https://[^\s)]+"#
    private static let errorTailLength = 200
    private static let oauthHostHints = ["oauth", "accounts.google.com", "auth.openai.com"]

    /// `codex login` spawn → URL 추출 + 브라우저 오픈 → polling.
    public static func loginCodex(
        codexPath: URL,
        checker: EnvironmentChecker = EnvironmentChecker(),
        pollInterval: TimeInterval = 2,
        timeout: TimeInterval = 300
    ) async -> LoginResult {
        await runOAuthSubprocess(
            executable: codexPath,
            arguments: ["login"],
            initialStdin: nil,
            authCheck: { await checker.checkCodexAuth().isReady },
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
        await runOAuthSubprocess(
            executable: geminiPath,
            arguments: ["-p", "ping", "--yolo", "--skip-trust"],
            initialStdin: "Y\n",
            authCheck: { await checker.checkGeminiAuth().isReady },
            pollInterval: pollInterval,
            timeout: timeout
        )
    }

    // MARK: - Private

    // 공통 OAuth subprocess 실행 + output 모니터링 + URL 자동 오픈.
    // swiftlint:disable:next function_body_length cyclomatic_complexity function_parameter_count
    private static func runOAuthSubprocess(
        executable: URL,
        arguments: [String],
        initialStdin: String?,
        authCheck: @escaping @Sendable () async -> Bool,
        pollInterval: TimeInterval,
        timeout: TimeInterval
    ) async -> LoginResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let inputPipe: Pipe? = initialStdin != nil ? Pipe() : nil
        if let inputPipe { process.standardInput = inputPipe }

        // stdout / stderr 누적 — 비동기 readabilityHandler.
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
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
        } catch {
            return .processFailed(message: "실행 실패: \(error.localizedDescription)")
        }

        // 일부 CLI (Gemini) 는 prompt 출력 후 stdin 응답 대기 — 미리 Y\n 주입.
        if let inputPipe, let payload = initialStdin?.data(using: .utf8) {
            try? inputPipe.fileHandleForWriting.write(contentsOf: payload)
            try? inputPipe.fileHandleForWriting.close()
        }

        var openedURL = false
        let deadline = Date().addingTimeInterval(timeout)
        let pollNanos = UInt64(pollInterval * 1_000_000_000)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: pollNanos)
            } catch {
                terminateIfRunning(process)
                return .cancelled
            }
            if Task.isCancelled {
                terminateIfRunning(process)
                return .cancelled
            }
            // OAuth URL 자동 오픈 (한 번만) — Codex 백업 경로. Gemini 는 URL 안 찍음.
            if !openedURL, let url = Self.extractOAuthURL(from: accumulator.snapshot()) {
                let opened = await MainActor.run { NSWorkspace.shared.open(url) }
                openedURL = true
                if !opened {
                    // v0.9.8: 브라우저 오픈 실패 — 5분 대기 대신 즉시 사용자에게 알림.
                    terminateIfRunning(process)
                    return .browserOpenFailed(url: url)
                }
            }
            if await authCheck() {
                terminateIfRunning(process)
                return .success
            }
            if !process.isRunning {
                let exitCode = process.terminationStatus
                if exitCode == 0 {
                    return .cancelled
                }
                let snapshot = accumulator.snapshot()
                let cliName = executable.lastPathComponent
                return .processFailed(
                    message: "\(cliName) exit \(exitCode): \(snapshot.suffix(errorTailLength))"
                )
            }
        }
        terminateIfRunning(process)
        return .timedOut
    }

    /// stdout/stderr 에서 첫 OAuth URL 추출.
    /// Codex: `https://auth.openai.com/oauth/authorize?...`
    /// Gemini: URL 안 찍어서 사용 안 함 (Gemini 가 직접 브라우저 오픈).
    static func extractOAuthURL(from text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var fallback: String?
        // v0.9.8: 단일 패스 — OAuth 패턴 발견 시 즉시 반환, 없으면 첫 https 를 fallback 으로 보존.
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
