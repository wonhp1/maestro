import Darwin
import Foundation

/// 현재 프로세스의 PATH 환경변수를 사용자 로그인 쉘 PATH 와 머지.
///
/// macOS .app 으로 실행된 Maestro 가 `claude` / `aider` 같은 사용자 설치 CLI 를
/// 발견할 수 있도록 앱 시작 시 한 번 호출. `LoginShellPathExtractor` 결과를
/// `setenv("PATH", merged, 1)` 로 적용 — `ProcessInfo.processInfo.environment` 도
/// 즉시 반영됨 (Foundation 이 매번 `getenv` 로 읽음).
///
/// **순서 보장**: 현재 PATH 가 우선 (먼저 등장), 그 뒤에 로그인 쉘 PATH 의 신규
/// 항목만 append. 시스템 디렉토리가 사용자 디렉토리를 가리지 않도록.
///
/// **PATH-poisoning 방어**: 추가 항목은 절대경로 + 디렉토리 존재 + 표준 prefix
/// 화이트리스트로 한 번 더 거른다 (`~/.zshrc` 가 `/tmp/attacker` 를 PATH 에 박는
/// 시나리오 차단).
public enum EnvironmentAugmenter {
    /// `LoginShellPathExtractor` 로 추출한 PATH 를 현재 프로세스 PATH 에 머지.
    /// 이미 호출된 적 있으면 no-op (idempotent). `setenv` 실패 시 flag 유지하지 않음.
    @discardableResult
    public static func augmentPATHFromLoginShell(
        extractor: LoginShellPathExtractor = LoginShellPathExtractor()
    ) async -> AugmentResult {
        if hasAugmented.load() { return .alreadyAugmented }
        let additions: [String]
        do {
            additions = try await extractor.extract()
        } catch {
            return .extractFailed(error: error)
        }
        return apply(additions: additions)
    }

    /// 순수 동기 변형 — `@main App init()` 에서 호출. `async`/Task/DispatchSemaphore
    /// 조합이 SwiftUI App init 컨텍스트에서 race / 데드락을 일으키는 footgun 회피.
    /// `Process.waitUntilExit` 으로 직접 spawn → 결과 즉시 반환.
    /// - Parameter timeout: shell 응답 대기 (초). 기본 2.0.
    @discardableResult
    public static func augmentPATHFromLoginShellSync(
        shellURL: URL = LoginShellPathExtractor.defaultShellURL(),
        timeout: TimeInterval = 2.0
    ) -> AugmentResult {
        if hasAugmented.load() { return .alreadyAugmented }
        let additions: [String]
        do {
            additions = try extractPathSync(shellURL: shellURL, timeout: timeout)
        } catch {
            return .extractFailed(error: error)
        }
        return apply(additions: additions)
    }

    /// 동기 spawn — Process.run + waitUntilExit, timeout 지나면 SIGKILL.
    /// `-ilc` 사용: interactive (`.zshrc` 강제 로드) + login (`.zprofile`) + command.
    /// `-lc` 만 쓰면 비대화형이라 zsh 가 `.zshrc` 를 건너뜀 → 사용자가 거기 추가한
    /// PATH (`~/.npm-global/bin` 등) 가 누락되는 v0.4.3 의 진짜 원인이었음.
    private static func extractPathSync(shellURL: URL, timeout: TimeInterval) throws -> [String] {
        let process = Process()
        process.executableURL = shellURL
        process.arguments = ["-ilc", "echo $PATH"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        process.environment = EnvironmentSanitizer.default.sanitizedProcessEnvironment()
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw LoginShellPathExtractorError.timedOut
        }
        let data = stdoutPipe.fileHandleForReading.availableData
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw LoginShellPathExtractorError.shellFailed(
                exitCode: process.terminationStatus,
                stderr: ""
            )
        }
        return LoginShellPathExtractor.parse(raw)
    }

    /// merge + sanitize + setenv 공통 경로 — async/sync 양쪽에서 사용.
    private static func apply(additions: [String]) -> AugmentResult {
        let current = parseCurrentPATH()
        let filtered = sanitize(additions)
        let merged = merge(current: current, additions: filtered)
        guard setPATH(merged) else {
            return .setenvFailed(errno: errno)
        }
        hasAugmented.store(true)
        return .augmented(addedCount: merged.count - current.count)
    }

    /// 현재 PATH 와 로그인 쉘 PATH 머지 — 현재 PATH 우선, 신규 항목만 append, dedupe.
    public static func merge(current: [String], additions: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in current + additions where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }

    /// 콜론으로 join — `setenv` 에 넣을 형식.
    public static func format(_ paths: [String]) -> String {
        paths.joined(separator: ":")
    }

    /// 추가 후보 PATH 항목을 안전성 검증 — 절대경로 + 디렉토리 존재 + 표준 prefix.
    /// 통과 못 하면 drop. `~/.zshrc` PATH-poisoning 차단.
    public static func sanitize(
        _ paths: [String],
        fileManager: FileManager = .default
    ) -> [String] {
        let allowedPrefixes = [
            "/bin", "/sbin", "/usr/", "/opt/", "/Library/",
            FileManager.default.homeDirectoryForCurrentUser.path,
        ]
        return paths.filter { path in
            guard path.hasPrefix("/") else { return false }
            guard allowedPrefixes.contains(where: { path.hasPrefix($0) }) else { return false }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue else {
                return false
            }
            return true
        }
    }

    /// 테스트 전용 — augmentation flag 리셋. process global state 누수 방지.
    static func resetForTesting() {
        hasAugmented.store(false)
    }

    private static func parseCurrentPATH() -> [String] {
        let raw = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return LoginShellPathExtractor.parse(raw)
    }

    /// `setenv` 호출. 성공이면 true, 실패면 false (errno 외부에서 확인).
    private static func setPATH(_ paths: [String]) -> Bool {
        let joined = format(paths)
        let result = joined.withCString { setenv("PATH", $0, 1) }
        return result == 0
    }

    /// 일회성 가드 — actor 없는 단순 atomic flag.
    private static let hasAugmented = AugmentationFlag()
}

/// `EnvironmentAugmenter.augmentPATHFromLoginShell` 의 결과.
public enum AugmentResult: Sendable {
    case augmented(addedCount: Int)
    case alreadyAugmented
    case extractFailed(error: Error)
    case setenvFailed(errno: Int32)
}

/// 단순 atomic boolean — `OSAtomic` deprecated 후 `os_unfair_lock` 로 충분.
/// 이름 충돌 회피로 `AugmentationFlag` (ProcessStreamer 내부의 `AtomicFlag` 와 분리).
private final class AugmentationFlag: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var value = false

    func load() -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }

    func store(_ newValue: Bool) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value = newValue
    }
}
