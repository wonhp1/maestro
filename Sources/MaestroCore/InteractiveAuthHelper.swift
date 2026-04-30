import Foundation

/// v0.9.2 — 인앱 OAuth 로그인 도우미.
///
/// Codex CLI 의 `codex login` 은 자동으로 브라우저를 열고 localhost:1455 에서
/// callback 을 받음. Maestro 는 subprocess 만 spawn 하고, 백그라운드에서 인증
/// 상태를 polling 하다가 성공하면 종료.
///
/// 사용자 경험:
/// 1. Maestro 의 "로그인" 버튼 클릭
/// 2. 브라우저 자동 열림 → ChatGPT 계정으로 로그인
/// 3. 로그인 완료 시 Maestro UI 자동 갱신 (banner 사라짐)
public enum InteractiveAuthHelper {
    /// 결과 — 성공 / 사용자 취소 / 시간 초과 / 프로세스 실패.
    public enum LoginResult: Sendable, Equatable {
        case success
        case cancelled
        case timedOut
        case processFailed(message: String)
    }

    /// `codex login` spawn + 인증 완료까지 polling.
    ///
    /// - Parameters:
    ///   - codexPath: `codex` 실행 파일 경로 (PATH 검색 결과)
    ///   - checker: 인증 상태 검사기
    ///   - pollInterval: 검사 주기 (default 2초)
    ///   - timeout: 전체 timeout (default 5분)
    /// - Returns: `LoginResult`
    public static func loginCodex(
        codexPath: URL,
        checker: EnvironmentChecker = EnvironmentChecker(),
        pollInterval: TimeInterval = 2,
        timeout: TimeInterval = 300
    ) async -> LoginResult {
        let process = Process()
        process.executableURL = codexPath
        process.arguments = ["login"]
        // stdout/stderr 캡처 — 디버깅용. URL 출력하지만 자동 브라우저 열림.
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .processFailed(message: "codex 실행 실패: \(error.localizedDescription)")
        }

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
            // 인증 성공 검사
            if await checker.checkCodexAuth().isReady {
                terminateIfRunning(process)
                return .success
            }
            // process 가 일찍 종료된 경우 (사용자가 ctrl-c 등)
            if !process.isRunning {
                let exitCode = process.terminationStatus
                if exitCode == 0 {
                    // 종료됐는데 auth 미완료 — 브라우저 닫음.
                    return .cancelled
                }
                let stderr = String(
                    data: errorPipe.fileHandleForReading.availableData,
                    encoding: .utf8
                ) ?? ""
                return .processFailed(message: "codex login exit \(exitCode): \(stderr.prefix(200))")
            }
        }
        terminateIfRunning(process)
        return .timedOut
    }

    /// `gemini` spawn + Google OAuth callback 까지 polling.
    ///
    /// Gemini 는 별도 `login` 명령이 없음 — 첫 prompt 호출 시 OAuth 자동 트리거.
    /// `-p "ping" --yolo --skip-trust` 로 최소 prompt 실행 (응답 받기 전에 auth 감지
    /// 시 process 종료, 토큰 소비 거의 0).
    public static func loginGemini(
        geminiPath: URL,
        checker: EnvironmentChecker = EnvironmentChecker(),
        pollInterval: TimeInterval = 2,
        timeout: TimeInterval = 300
    ) async -> LoginResult {
        let process = Process()
        process.executableURL = geminiPath
        process.arguments = ["-p", "ping", "--yolo", "--skip-trust"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .processFailed(message: "gemini 실행 실패: \(error.localizedDescription)")
        }

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
            if await checker.checkGeminiAuth().isReady {
                terminateIfRunning(process)
                return .success
            }
            if !process.isRunning {
                let exitCode = process.terminationStatus
                if exitCode == 0 {
                    return .cancelled
                }
                let stderr = String(
                    data: errorPipe.fileHandleForReading.availableData,
                    encoding: .utf8
                ) ?? ""
                return .processFailed(
                    message: "gemini exit \(exitCode): \(stderr.prefix(200))"
                )
            }
        }
        terminateIfRunning(process)
        return .timedOut
    }

    private static func terminateIfRunning(_ process: Process) {
        if process.isRunning {
            process.terminate()
        }
    }
}
