import Foundation

/// v0.8.0 — 환경 도구 자동 설치. Node.js .pkg / Claude (npm) / Aider (pip).
///
/// ## 책임
/// - `installNode()` — Node.js .pkg 다운로드 + sudo installer (osascript dialog)
/// - `installClaude()` — `npm install -g @anthropic-ai/claude-code` (AdapterInstaller 위임)
/// - `installAider()` — `pip3 install --user aider-chat` (AdapterInstaller 위임)
///
/// ## Idempotent
/// 호출자가 EnvironmentChecker 로 누락 확인 후 호출. 함수 자체는 멱등 X — 매번 실행.
///
/// ## sudo dialog
/// Node 설치 시 macOS 표준 `osascript ... with administrator privileges`. Maestro 가
/// 비밀번호 직접 다루지 않음. Touch ID 가능.
///
/// ## 테스트
/// `nodeDownloader` / `osascriptExecutor` / `adapterInstaller` 주입 — 모두 stub 가능.
public actor EnvironmentInstaller {
    /// Node.js LTS 의 universal2 (Apple Silicon + Intel) .pkg URL.
    /// 버전 픽스: ship 시점의 안정 LTS. 향후 업데이트는 코드 변경 + release.
    public static let defaultNodePackageURL = URL(
        string: "https://nodejs.org/dist/v22.11.0/node-v22.11.0.pkg"
    )!

    /// AdapterInstaller 의 install 결과를 반환하는 closure — testing 시 stub.
    public typealias AdapterInstallFunc = @Sendable (String) async throws -> AdapterInstallResult

    private let nodePackageURL: URL
    private let nodeDownloader: NodeDownloading
    private let sudoExecutor: SudoExecuting
    private let adapterInstall: AdapterInstallFunc

    public init(
        nodePackageURL: URL = EnvironmentInstaller.defaultNodePackageURL,
        nodeDownloader: NodeDownloading = URLSessionNodeDownloader(),
        sudoExecutor: SudoExecuting = OsascriptSudoExecutor(),
        adapterInstall: AdapterInstallFunc? = nil
    ) {
        self.nodePackageURL = nodePackageURL
        self.nodeDownloader = nodeDownloader
        self.sudoExecutor = sudoExecutor
        // default — 실제 AdapterInstaller delegation.
        let realInstaller = AdapterInstaller()
        self.adapterInstall = adapterInstall ?? { id in
            try await realInstaller.install(adapterId: id)
        }
    }

    // MARK: - Node.js

    /// Node.js .pkg 다운로드 + sudo installer 실행.
    /// progress 콜백: 다운로드 bytes / 설치 phase / 완료.
    public func installNode(
        progress: @Sendable (InstallProgress) -> Void = { _ in }
    ) async throws {
        progress(.running(phase: "Node.js 다운로드 중…"))
        let pkgURL = try await nodeDownloader.download(
            from: nodePackageURL,
            progress: { downloaded, total in
                progress(.downloading(bytes: downloaded, total: total))
            }
        )
        defer { try? FileManager.default.removeItem(at: pkgURL) }

        progress(.running(phase: "Node.js 설치 중… (sudo 비밀번호 필요)"))
        let command = Self.installerCommand(pkgPath: pkgURL.path)
        try await sudoExecutor.runWithAdminPrivileges(
            command: command,
            prompt: "Maestro 가 Node.js 를 설치하려고 합니다."
        )
        progress(.complete)
    }

    // MARK: - Claude / Aider — AdapterInstaller 위임

    public func installClaude(
        progress: @Sendable (InstallProgress) -> Void = { _ in }
    ) async throws {
        progress(.running(phase: "Claude Code 설치 중…"))
        let result = try await adapterInstall("claude")
        try Self.assertSuccess(result)
        progress(.complete)
    }

    public func installAider(
        progress: @Sendable (InstallProgress) -> Void = { _ in }
    ) async throws {
        progress(.running(phase: "Aider 설치 중…"))
        let result = try await adapterInstall("aider")
        try Self.assertSuccess(result)
        progress(.complete)
    }

    // MARK: - Helpers

    /// `installer -pkg <path> -target /` — pure logic for testing.
    public static func installerCommand(pkgPath: String) -> String {
        // pkgPath 의 single quote 가 sh-escape — embedded ' → '\''
        let escaped = pkgPath.replacingOccurrences(of: "'", with: "'\\''")
        return "/usr/sbin/installer -pkg '\(escaped)' -target /"
    }

    private static func assertSuccess(_ result: AdapterInstallResult) throws {
        if case let .failed(exitCode, stderr) = result {
            throw EnvironmentInstallerError.installFailed(
                exitCode: exitCode,
                stderr: stderr
            )
        }
    }
}

/// 자동 설치 진행 상태.
public enum InstallProgress: Sendable, Equatable {
    case downloading(bytes: Int64, total: Int64?)
    case running(phase: String)
    case complete
}

public enum EnvironmentInstallerError: Error, Sendable, Equatable {
    case installFailed(exitCode: Int32, stderr: String)
    case downloadFailed(reason: String)
    case sudoCancelled
    case sudoFailed(reason: String)
}

// MARK: - NodeDownloading

/// .pkg 다운로드 추상화 — 테스트에서 stub.
public protocol NodeDownloading: Sendable {
    /// `from` 에서 다운로드 → 임시 파일 URL 반환. progress 콜백 (downloaded, total?) 호출.
    func download(
        from url: URL,
        progress: @Sendable (Int64, Int64?) -> Void
    ) async throws -> URL
}

/// URLSession 기반 다운로더. 600초 resource timeout — 50MB 다운로드가 느린 망에서도 충분.
public struct URLSessionNodeDownloader: NodeDownloading {
    /// .pkg 가 0-byte / corrupt 일 가능성 차단 — 실제 Node.js .pkg 는 ~30-60MB.
    /// 10MB 미만이면 비정상 (CDN 에러 page 등) → throw.
    public static let minimumPkgBytes: Int64 = 10 * 1024 * 1024

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 600  // 10분 — 느린 망 대비
            self.session = URLSession(configuration: config)
        }
    }

    public func download(
        from url: URL,
        progress: @Sendable (Int64, Int64?) -> Void
    ) async throws -> URL {
        let (tempURL, response) = try await session.download(from: url)
        // L1 — moveItem 실패 시 tempURL leak 방지.
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
        let downloaded = (attrs?[.size] as? Int64) ?? 0
        progress(downloaded, total)
        // M1 — minimum size guard (corrupt 0-byte / HTML error page 차단).
        if downloaded < Self.minimumPkgBytes {
            throw EnvironmentInstallerError.downloadFailed(
                reason: "다운로드 크기 비정상 (\(downloaded) bytes, 최소 \(Self.minimumPkgBytes) 기대)"
            )
        }
        // 명시적 dest 로 move — URLSession 임시 파일은 caller 의 cleanup defer 가 책임.
        let dest = FileManager.default.temporaryDirectory
            .appending(path: "maestro-node-\(UUID().uuidString).pkg", directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }
}

// MARK: - SudoExecuting (osascript)

/// sudo 실행 추상화 — 테스트에서 mock.
public protocol SudoExecuting: Sendable {
    /// shell command 를 administrator privileges 로 실행. 사용자가 cancel 하면
    /// `EnvironmentInstallerError.sudoCancelled` throw.
    func runWithAdminPrivileges(command: String, prompt: String) async throws
}

/// `osascript -e 'do shell script ... with administrator privileges'` 기반 실행.
/// macOS 표준 인증 dialog (Touch ID 가능).
public struct OsascriptSudoExecutor: SudoExecuting {
    private let executor: any ProcessExecuting

    public init(executor: any ProcessExecuting = DefaultProcessExecutor(timeout: 600)) {
        self.executor = executor
    }

    public func runWithAdminPrivileges(command: String, prompt: String) async throws {
        let script = Self.appleScript(command: command, prompt: prompt)
        let output: ProcessOutput
        do {
            output = try await executor.run(
                executable: URL(filePath: "/usr/bin/osascript"),
                arguments: ["-e", script]
            )
        } catch {
            throw EnvironmentInstallerError.sudoFailed(reason: String(describing: error))
        }
        guard output.exitCode == 0 else {
            // 사용자 취소 감지 — locale 차이 안전. macOS 의 osascript 가 cancel 시
            // exit 1 또는 128 + stderr 에 "-128" 또는 "user canceled" 류 (로케일별 변형).
            let stderr = output.stderr
            if [1, 128].contains(output.exitCode),
               stderr.contains("-128")
                || stderr.localizedCaseInsensitiveContains("user canceled")
                || stderr.localizedCaseInsensitiveContains("취소") {
                throw EnvironmentInstallerError.sudoCancelled
            }
            throw EnvironmentInstallerError.sudoFailed(
                reason: "osascript exit \(output.exitCode): \(stderr.suffix(500))"
            )
        }
    }

    /// AppleScript 빌드 — command 와 prompt 의 double-quote/backslash escape.
    public static func appleScript(command: String, prompt: String) -> String {
        let cmdEscaped = escape(command)
        let promptEscaped = escape(prompt)
        return "do shell script \"\(cmdEscaped)\" with prompt \"\(promptEscaped)\" with administrator privileges"
    }

    /// AppleScript double-quoted string 안에 안전하게 들어가도록 escape.
    /// - `\` → `\\`
    /// - `"` → `\"`
    public static func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
