import Foundation

/// 사용자 진단 번들 — 설정 / 로그 / 레지스트리 등을 한 ZIP 파일로 묶음.
///
/// ## 동기
/// 사용자가 버그 보고 시 "Diagnostic Bundle 만들기" 한 번으로 시스템/앱 정보 +
/// 관련 파일들을 수집해 첨부 가능. 민감 정보(시크릿/Keychain)는 **포함하지 않음**.
///
/// ## 구성
/// - `manifest.json`: 앱/OS/생성시각 + 포함된 파일 목록
/// - `paths/<name>/...`: 각 source path 의 복사본 (Keychain 제외 — 디스크에 없음)
///
/// ## 보안
/// - 시크릿이 디스크에 평문으로 존재하면 그대로 포함됨 — 호출자가 sourcePaths 선택
///   시 신중히 결정. Maestro 자체는 envelope/threads 만 평문으로 두므로 안전.
/// - ZIP 자체는 암호화하지 않음 — 사용자가 외부에 전달 시 책임.
///
/// - SeeAlso: `MaestroLogger` (런타임 로깅)
/// - SeeAlso: `ProcessExecuting` (ZIP 도구 실행)
public actor DiagnosticsBundle {
    public struct Manifest: Codable, Hashable, Sendable {
        public let appName: String
        public let appVersion: String
        public let bundleIdentifier: String
        public let macOSVersionString: String
        public let createdAt: Date
        /// ZIP 안의 상대 경로들 (예: `paths/registry/registry.json`).
        public let includedRelativePaths: [String]

        public init(
            appName: String,
            appVersion: String,
            bundleIdentifier: String,
            macOSVersionString: String,
            createdAt: Date,
            includedRelativePaths: [String]
        ) {
            self.appName = appName
            self.appVersion = appVersion
            self.bundleIdentifier = bundleIdentifier
            self.macOSVersionString = macOSVersionString
            self.createdAt = createdAt
            self.includedRelativePaths = includedRelativePaths
        }
    }

    private let executor: any ProcessExecuting
    private let zipExecutable: URL
    private let logger: MaestroLogger

    /// - Parameters:
    ///   - executor: ZIP 실행에 쓸 프로세스 실행기. 기본 `DefaultProcessExecutor`.
    ///   - zipExecutable: ZIP 바이너리 경로. 기본 `/usr/bin/zip` (macOS 기본 제공).
    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(timeout: 60),
        zipExecutable: URL = URL(fileURLWithPath: "/usr/bin/zip")
    ) {
        self.executor = executor
        self.zipExecutable = zipExecutable
        self.logger = MaestroLogger(category: .general)
    }

    /// 진단 번들 ZIP 생성.
    ///
    /// - Parameters:
    ///   - outputZipURL: 생성할 ZIP 파일의 최종 경로. 부모 디렉토리는 미리 존재해야 함.
    ///   - sourcePaths: 포함할 파일 또는 디렉토리들. 누락된 경로는 manifest 에서 제외.
    ///   - now: 시각 (테스트 주입용).
    /// - Returns: 번들에 기록된 manifest (호출자도 별도 활용 가능).
    public func create(
        outputZipURL: URL,
        sourcePaths: [URL],
        now: Date = Date()
    ) async throws -> Manifest {
        // Phase 5 must-fix: zip 실행파일 존재 사전 확인 — launchFailed 보다 명확한 에러.
        guard FileManager.default.isExecutableFile(atPath: zipExecutable.path) else {
            throw DiagnosticsBundleError.missingZipExecutable(zipExecutable)
        }

        let staging = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }

        var includedRelative: [String] = []
        let pathsRoot = staging.appending(path: "paths", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pathsRoot, withIntermediateDirectories: true)

        // Phase 5 must-fix: outputZipURL 이 source 트리 내부면 zip 이 자기 출력을 재귀 — 거부.
        let outputResolved = outputZipURL.resolvingSymlinksInPath().standardizedFileURL
        for source in sourcePaths {
            let srcResolved = source.resolvingSymlinksInPath().standardizedFileURL
            if outputResolved.path.hasPrefix(srcResolved.path + "/")
                || outputResolved.path == srcResolved.path {
                throw DiagnosticsBundleError.outputInsideSource(
                    output: outputZipURL,
                    source: source
                )
            }
        }

        // 중복 lastPathComponent 처리 — index 접두사로 충돌 회피.
        var nameUsage: [String: Int] = [:]
        for source in sourcePaths {
            guard FileManager.default.fileExists(atPath: source.path) else {
                logger.warning("source path missing, skipped: \(source.path)")
                continue
            }
            let baseName = source.lastPathComponent
            let count = nameUsage[baseName, default: 0]
            nameUsage[baseName] = count + 1
            let destName = count == 0 ? baseName : "\(count)-\(baseName)"
            let dest = pathsRoot.appending(path: destName)
            do {
                try FileManager.default.copyItem(at: source, to: dest)
                includedRelative.append("paths/\(destName)")
            } catch {
                logger.warning("copy failed for \(baseName): \(String(describing: error))")
            }
        }

        let manifest = Manifest(
            appName: MaestroConfig.appName,
            appVersion: MaestroConfig.appVersion,
            bundleIdentifier: MaestroConfig.bundleIdentifier,
            macOSVersionString: ProcessInfo.processInfo.operatingSystemVersionString,
            createdAt: now,
            includedRelativePaths: includedRelative
        )
        let manifestURL = staging.appending(path: "manifest.json")
        let manifestData = try JSONEncoder.maestro.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        // 기존 ZIP 이 있으면 제거 (zip 은 append 가 default).
        try? FileManager.default.removeItem(at: outputZipURL)

        // /usr/bin/zip -rq <out> manifest.json paths — staging 디렉토리에서 실행.
        let output = try await executor.run(
            executable: zipExecutable,
            arguments: ["-rq", outputZipURL.path, "manifest.json", "paths"],
            currentDirectoryURL: staging
        )
        guard output.exitCode == 0 else {
            throw DiagnosticsBundleError.zipFailed(exitCode: output.exitCode, stderr: output.stderr)
        }
        return manifest
    }

    /// 0700 권한 staging 디렉토리 (다른 사용자 접근 차단). $TMPDIR 가 비표준일 때 보호.
    private func makeStagingDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appending(
            path: "maestro-diagnostics-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }
}

public enum DiagnosticsBundleError: Error, Equatable, Sendable {
    case zipFailed(exitCode: Int32, stderr: String)
    case missingZipExecutable(URL)
    /// outputZipURL 이 sourcePaths 중 하나의 내부 또는 동일 경로 — 무한 재귀 방지.
    case outputInsideSource(output: URL, source: URL)
}
