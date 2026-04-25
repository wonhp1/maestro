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
