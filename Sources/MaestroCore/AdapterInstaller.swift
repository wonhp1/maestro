import Foundation

/// 미설치 어댑터를 사용자 한 번 클릭으로 자동 설치 — npm / pip 호출.
///
/// ## 디자인
/// - 알려진 어댑터별 install spec (`AdapterInstallSpec`) 정의
/// - `install(adapterId:)` → 패키지 매니저 PATH 검색 → spawn → 결과 반환
/// - 패키지 매니저 자체가 없으면 `AdapterInstallerError.packageManagerMissing` (사용자에게
///   Node / Python 설치 안내 책임은 호출자)
///
/// ## 비동기 / 진행률
/// 출력은 `executor.run()` 의 stdout 으로 받음 — 스트리밍 진행률은 향후 ProcessStreaming
/// wrapper 로 확장 (현재는 완료 후 일괄).
public struct AdapterInstaller: Sendable {
    private let packageManagerLocator: @Sendable (String) -> URL?
    private let executor: any ProcessExecuting
    private let timeout: TimeInterval

    public init(
        packageManagerLocator: @escaping @Sendable (String) -> URL? =
            AdapterInstaller.defaultPackageManagerLocator,
        executor: (any ProcessExecuting)? = nil,
        timeout: TimeInterval = 300  // 5분 — npm install 대형 패키지 대비
    ) {
        self.packageManagerLocator = packageManagerLocator
        self.executor = executor ?? DefaultProcessExecutor(timeout: timeout)
        self.timeout = timeout
    }

    /// PATH 에서 패키지 매니저 (`npm` / `pip` / `pip3`) 를 찾는 기본 구현.
    public static let defaultPackageManagerLocator: @Sendable (String) -> URL? = { name in
        PATHExecutableLocator().locate(name)
    }

    /// 알려진 어댑터의 install spec. 미지원 어댑터는 nil.
    public static func spec(for adapterId: String) -> AdapterInstallSpec? {
        switch adapterId {
        case "claude":
            return AdapterInstallSpec(
                packageManager: "npm",
                installArguments: ["install", "-g", "@anthropic-ai/claude-code"]
            )
        case "aider":
            return AdapterInstallSpec(
                packageManager: "pip3",
                installArguments: ["install", "--user", "aider-chat"]
            )
        default:
            return nil
        }
    }

    /// 자동 설치 실행. throws 는 시스템 레벨 에러 (패키지 매니저 부재 / 미지원 어댑터);
    /// 설치 자체가 non-zero 종료한 경우는 `.failed` 반환.
    public func install(adapterId: String) async throws -> AdapterInstallResult {
        guard let spec = Self.spec(for: adapterId) else {
            throw AdapterInstallerError.unsupportedAdapter(id: adapterId)
        }
        guard let pmURL = packageManagerLocator(spec.packageManager) else {
            // pip3 가 없으면 pip 도 시도
            if spec.packageManager == "pip3", let alt = packageManagerLocator("pip") {
                return try await runInstall(executable: alt, arguments: spec.installArguments)
            }
            throw AdapterInstallerError.packageManagerMissing(name: spec.packageManager)
        }
        return try await runInstall(executable: pmURL, arguments: spec.installArguments)
    }

    private func runInstall(executable: URL, arguments: [String]) async throws -> AdapterInstallResult {
        let output: ProcessOutput
        do {
            output = try await executor.run(
                executable: executable,
                arguments: arguments,
                currentDirectoryURL: nil,
                environment: nil  // PATH 정상 발견을 위해 부모 환경 그대로 (sanitizer X — install 은 로컬 패키지 매니저)
            )
        } catch ProcessExecutionError.timedOut {
            return .failed(exitCode: -1, stderr: "설치 시간 초과")
        } catch {
            throw AdapterInstallerError.spawnFailed(reason: String(describing: error))
        }
        if output.exitCode == 0 {
            return .success(stdoutTail: String(output.stdout.suffix(2048)))
        }
        return .failed(exitCode: output.exitCode, stderr: String(output.stderr.suffix(2048)))
    }
}

public struct AdapterInstallSpec: Sendable, Equatable {
    public let packageManager: String
    public let installArguments: [String]

    public init(packageManager: String, installArguments: [String]) {
        self.packageManager = packageManager
        self.installArguments = installArguments
    }
}

public enum AdapterInstallResult: Sendable, Equatable {
    case success(stdoutTail: String)
    case failed(exitCode: Int32, stderr: String)
}

public enum AdapterInstallerError: Error, Equatable, Sendable {
    case unsupportedAdapter(id: String)
    case packageManagerMissing(name: String)
    case spawnFailed(reason: String)
}
