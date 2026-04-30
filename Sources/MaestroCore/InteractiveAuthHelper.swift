import AppKit
import Foundation

/// v0.9.4 — 인앱 OAuth 로그인 도우미.
///
/// CLI subprocess 가 자동 브라우저 오픈 시도하지만, Pipe 로 stdout/stderr 캡처
/// 되면 자동 오픈이 작동 안 함. 해결: subprocess output 에서 OAuth URL 추출 →
/// `NSWorkspace.shared.open(url)` 로 직접 브라우저 호출.
///
/// 사용자 경험:
/// 1. Maestro 의 "로그인" 버튼 클릭
/// 2. 브라우저 자동 열림 (Maestro 가 URL 파싱해서 직접 호출)
/// 3. 로그인 후 Maestro 가 polling 해서 자동 갱신
public enum InteractiveAuthHelper {
    public enum LoginResult: Sendable, Equatable {
        case success
        case cancelled
        case timedOut
        case processFailed(message: String)
    }

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
            authCheck: { await checker.checkCodexAuth().isReady },
            pollInterval: pollInterval,
            timeout: timeout
        )
    }

    /// `gemini -p "ping" --yolo --skip-trust` spawn → URL 추출 + 브라우저 오픈 → polling.
    /// Gemini 는 별도 login 명령 없음 — 첫 prompt 호출 시 OAuth 자동 트리거.
    public static func loginGemini(
        geminiPath: URL,
        checker: EnvironmentChecker = EnvironmentChecker(),
        pollInterval: TimeInterval = 2,
        timeout: TimeInterval = 300
    ) async -> LoginResult {
        await runOAuthSubprocess(
            executable: geminiPath,
            arguments: ["-p", "ping", "--yolo", "--skip-trust"],
            authCheck: { await checker.checkGeminiAuth().isReady },
            pollInterval: pollInterval,
            timeout: timeout
        )
    }

    // MARK: - Private

    // 공통 OAuth subprocess 실행 + output 모니터링 + URL 자동 오픈.
    // swiftlint:disable:next function_body_length
    private static func runOAuthSubprocess(
        executable: URL,
        arguments: [String],
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
            // OAuth URL 자동 오픈 (한 번만)
            if !openedURL, let url = Self.extractOAuthURL(from: accumulator.snapshot()) {
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
                openedURL = true
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
                return .processFailed(
                    message: "exit \(exitCode): \(snapshot.suffix(200))"
                )
            }
        }
        terminateIfRunning(process)
        return .timedOut
    }

    /// stdout/stderr 에서 첫 OAuth URL 추출.
    /// Codex: `https://auth.openai.com/oauth/authorize?...`
    /// Gemini: `https://accounts.google.com/o/oauth2/...`
    static func extractOAuthURL(from text: String) -> URL? {
        let pattern = #"https://[^\s)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let candidate = String(text[r])
            // OAuth 패턴 우선 (auth.openai.com 또는 accounts.google.com)
            if candidate.contains("oauth") || candidate.contains("accounts.google.com")
                || candidate.contains("auth.openai.com") {
                return URL(string: candidate)
            }
        }
        // OAuth 패턴 없으면 첫 번째 https URL
        if let first = matches.first,
           let r = Range(first.range, in: text) {
            return URL(string: String(text[r]))
        }
        return nil
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
