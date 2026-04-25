import Foundation

/// 사용자의 로그인 쉘 (`zsh -lc`) 의 PATH 를 추출.
///
/// macOS .app 으로 실행된 프로세스는 `launchd` 가 부여한 최소 PATH
/// (`/usr/bin:/bin:/usr/sbin:/sbin`) 만 상속함. 사용자가 `~/.zshrc` 등에서 추가한
/// `/opt/homebrew/bin`, `~/.npm-global/bin` 같은 경로는 보이지 않음 — 즉,
/// `claude` (npm-global 설치) 나 `aider` (homebrew/pip 설치) 를 PATH 에서 못 찾음.
///
/// 이 추출기는 사용자의 인터랙티브 쉘을 한 번 spawn 해서 그 PATH 를 가져온 뒤
/// `EnvironmentAugmenter` 가 현재 프로세스 환경에 머지한다.
///
/// ## 보안
/// - `$SHELL` 환경변수는 신뢰하지 않는다 — `defaultShellURL()` 가 `/etc/shells`
///   엔트리 또는 표준 시스템 디렉토리 (`/bin`, `/usr/bin`, `/opt/homebrew/bin`) 로
///   제한. 위반 시 `/bin/zsh` 폴백.
/// - 자식 환경은 `EnvironmentSanitizer.default.sanitizedProcessEnvironment()` 로
///   삭제 — `~/.zshrc` 가 시크릿 (CLAUDE_API_KEY 등) 을 외부로 누출 못 하게.
/// - 추출된 PATH 항목은 `EnvironmentAugmenter.merge` 단에서 절대경로 + 디렉토리
///   존재 검증으로 한 번 더 거른다.
public struct LoginShellPathExtractor: Sendable {
    public let shellURL: URL
    public let timeout: TimeInterval
    private let executor: any ProcessExecuting
    private let environment: [String: String]

    public init(
        shellURL: URL? = nil,
        timeout: TimeInterval = 3.0,
        executor: (any ProcessExecuting)? = nil,
        environment: [String: String]? = nil
    ) {
        self.shellURL = shellURL ?? Self.defaultShellURL()
        self.timeout = timeout
        // 호출자가 executor 주입 안 하면 timeout 으로 새 executor 생성 — 기존 패턴은
        // default param 으로 표현 못 함 (Swift 가 다른 param 을 default 로 못 참조).
        self.executor = executor ?? DefaultProcessExecutor(timeout: timeout)
        self.environment = environment ?? EnvironmentSanitizer.default.sanitizedProcessEnvironment()
    }

    /// `$SHELL` 검증 — `/etc/shells` 또는 표준 디렉토리에 있는 경우만 사용. 외 `/bin/zsh`.
    public static func defaultShellURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let fallback = URL(fileURLWithPath: "/bin/zsh")
        guard let raw = env["SHELL"], !raw.isEmpty else { return fallback }
        let candidate = URL(fileURLWithPath: raw).standardizedFileURL
        guard isAllowedShell(candidate, fileManager: fileManager) else { return fallback }
        return candidate
    }

    /// 표준 시스템 디렉토리 prefix + 실행 가능 + 일반 파일 검증.
    static func isAllowedShell(_ url: URL, fileManager: FileManager) -> Bool {
        let allowedPrefixes = [
            "/bin/", "/usr/bin/", "/usr/local/bin/", "/opt/homebrew/bin/",
        ]
        let path = url.path
        guard allowedPrefixes.contains(where: { path.hasPrefix($0) }) else { return false }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir),
              !isDir.boolValue,
              fileManager.isExecutableFile(atPath: path) else {
            return false
        }
        return true
    }

    /// 로그인 쉘의 PATH 를 추출. 실패 시 throws.
    /// - Returns: 콜론으로 분리하고 dedupe 된 path 컴포넌트.
    public func extract() async throws -> [String] {
        let output: ProcessOutput
        do {
            output = try await executor.run(
                executable: shellURL,
                arguments: ["-ilc", "echo $PATH"],
                currentDirectoryURL: nil,
                environment: environment
            )
        } catch ProcessExecutionError.timedOut {
            throw LoginShellPathExtractorError.timedOut
        } catch let processError as ProcessExecutionError {
            throw LoginShellPathExtractorError.spawnFailed(underlying: processError)
        } catch {
            throw LoginShellPathExtractorError.spawnFailed(
                underlying: ProcessExecutionError.launchFailed(reason: String(describing: error))
            )
        }
        guard output.exitCode == 0 else {
            throw LoginShellPathExtractorError.shellFailed(
                exitCode: output.exitCode,
                stderr: String(output.stderr.prefix(2048))  // 시크릿 누출 방지 cap
            )
        }
        return Self.parse(output.stdout)
    }

    /// 콜론으로 split → trim → 빈 컴포넌트 제거 → dedupe (첫 등장 우선).
    public static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for component in raw.split(separator: ":", omittingEmptySubsequences: false) {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}

public enum LoginShellPathExtractorError: Error, Equatable, Sendable {
    case timedOut
    case spawnFailed(underlying: ProcessExecutionError)
    case shellFailed(exitCode: Int32, stderr: String)
}
