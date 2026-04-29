import Foundation

/// v0.8.0 — 모든 환경 도구의 설치/버전 상태를 한 번 호출로 검사.
///
/// `CLIDetector` 는 어댑터 (Claude / Aider) 만 — Node / git / python 같은 환경 의존성은
/// 포괄 안 함. EnvironmentChecker 가 그 위 wrapper 로 모든 도구를 한 번에 검사.
///
/// ## 동시성
/// `checkAll()` 이 TaskGroup 으로 도구별 검사를 병렬 실행 — 전체 cost ≈ 가장 느린 단일 검사.
///
/// ## 테스트
/// `ProcessExecuting` 과 `ExecutableLocating` 주입 — stub 으로 시나리오별 테스트 가능.
public struct EnvironmentChecker: Sendable {
    /// Claude Code 의 최소 Node.js 버전 (engines.node 기준).
    public static let minNodeVersion = "v18"
    /// Aider 의 최소 Python 버전.
    public static let minPython3Version = "3.10"

    private let locator: any ExecutableLocating
    private let executor: any ProcessExecuting
    private let homeDirectory: URL
    /// 환경변수 — API key fallback 검사용 (`OPENAI_API_KEY`, `GEMINI_API_KEY`).
    /// 테스트에서 주입 가능. nil = ProcessInfo 사용.
    private let environmentSnapshot: [String: String]

    public init(
        locator: any ExecutableLocating = PATHExecutableLocator(),
        executor: any ProcessExecuting = DefaultProcessExecutor(timeout: 5),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String]? = nil
    ) {
        self.locator = locator
        self.executor = executor
        self.homeDirectory = homeDirectory
        self.environmentSnapshot = environment ?? ProcessInfo.processInfo.environment
    }

    /// 모든 도구를 병렬 검사 — 결과 EnvironmentStatus 로 합침.
    public func checkAll() async -> EnvironmentStatus {
        async let node = checkNode()
        async let claude = checkClaude()
        async let git = checkGit()
        async let python3 = checkPython3()
        async let aider = checkAider()
        async let claudeAuth = checkClaudeAuth()
        async let codex = checkCodex()
        async let codexAuth = checkCodexAuth()
        async let gemini = checkGemini()
        async let geminiAuth = checkGeminiAuth()
        return await EnvironmentStatus(
            node: node,
            claude: claude,
            git: git,
            python3: python3,
            aider: aider,
            claudeAuth: claudeAuth,
            codex: codex,
            codexAuth: codexAuth,
            gemini: gemini,
            geminiAuth: geminiAuth
        )
    }

    // MARK: - 개별 도구 검사

    public func checkNode() async -> ToolStatus {
        await checkVersionedBinary(
            name: "node",
            versionArgs: ["--version"],
            minimumVersion: Self.minNodeVersion
        )
    }

    public func checkClaude() async -> ToolStatus {
        await checkVersionedBinary(
            name: "claude",
            versionArgs: ["--version"],
            minimumVersion: nil
        )
    }

    public func checkGit() async -> ToolStatus {
        // git 은 있음/없음만 — 버전 검사 X (모든 git 버전이 우리 use case 충분).
        if locator.locate("git") != nil {
            return .installed(version: nil)
        }
        return .notInstalled
    }

    public func checkPython3() async -> ToolStatus {
        await checkVersionedBinary(
            name: "python3",
            versionArgs: ["--version"],
            minimumVersion: Self.minPython3Version
        )
    }

    public func checkAider() async -> ToolStatus {
        // Aider 는 pip --user 로 설치되어 ~/Library/Python/X.Y/bin/aider 에 위치 가능.
        // PATH 에 없을 수 있으므로 user-local path 도 체크. 두 path 모두 versioned check
        // 통과하도록 helper 통일 (must-fix /team H2).
        if let path = locator.locate("aider") {
            return await checkVersionedAt(executable: path, minimumVersion: nil)
        }
        let userPyBin = homeDirectory
            .appending(path: "Library/Python", directoryHint: .isDirectory)
        if let aiderPath = findAiderInUserPython(under: userPyBin) {
            return await checkVersionedAt(executable: aiderPath, minimumVersion: nil)
        }
        return .notInstalled
    }

    // MARK: - Codex / Gemini (v0.9.0)

    /// Codex (OpenAI) CLI 설치 여부 + 버전.
    public func checkCodex() async -> ToolStatus {
        await checkVersionedBinary(
            name: "codex",
            versionArgs: ["--version"],
            minimumVersion: nil
        )
    }

    /// Codex 인증 — 우선순위:
    /// 1. `OPENAI_API_KEY` 환경변수 존재 (CLI 미설치라도 인정)
    /// 2. `codex login status` 실행 결과 — exit 0 + 명시적 positive 매칭 (must-fix D-HIGH).
    ///
    /// `codex login status` 는 미로그인 상태에서도 exit 0 를 반환 (이 명령 자체는 성공) —
    /// stdout 텍스트가 유일한 신호. 로케일 변동 / 문구 변경에 견고하도록:
    /// - exit ≠ 0 → notInstalled
    /// - negative 문구 ("not logged in" 등) 매치 → notInstalled
    /// - positive 문구 ("logged in", "authenticated", "✓") 매치 → installed
    /// - 그 외 (모호) → conservative 하게 notInstalled
    public func checkCodexAuth() async -> ToolStatus {
        if let key = environmentSnapshot["OPENAI_API_KEY"], !key.isEmpty {
            return .installed(version: nil)
        }
        guard let codexPath = locator.locate("codex") else { return .notInstalled }
        let output: ProcessOutput
        do {
            output = try await executor.run(
                executable: codexPath,
                arguments: ["login", "status"]
            )
        } catch {
            return .notInstalled
        }
        return Self.classifyCodexLoginStatus(output: output)
    }

    /// `codex login status` 출력 분류 — testable static helper.
    static func classifyCodexLoginStatus(output: ProcessOutput) -> ToolStatus {
        guard output.exitCode == 0 else { return .notInstalled }
        let combined = (output.stdout + output.stderr).lowercased()
        // Negative 우선 — 명시적 미로그인 문구.
        let negative = ["not logged in", "no active session", "no credentials", "logged out"]
        if negative.contains(where: { combined.contains($0) }) {
            return .notInstalled
        }
        // Positive — 알려진 로그인 indicator.
        let positive = ["logged in", "authenticated", "auth ok", "✓"]
        if positive.contains(where: { combined.contains($0) }) {
            return .installed(version: nil)
        }
        // 모호 → conservative.
        return .notInstalled
    }

    /// Gemini (Google) CLI 설치 여부 + 버전.
    public func checkGemini() async -> ToolStatus {
        await checkVersionedBinary(
            name: "gemini",
            versionArgs: ["--version"],
            minimumVersion: nil
        )
    }

    /// Gemini 인증 — 우선순위:
    /// 1. `GEMINI_API_KEY` 환경변수
    /// 2. `~/.gemini/oauth_creds.json` 존재 + 내용 있음 + valid JSON dict
    ///    (claudeAuth 와 대칭 — corrupt/empty stub 차단, /team B-nice-to-have).
    public func checkGeminiAuth() async -> ToolStatus {
        if let key = environmentSnapshot["GEMINI_API_KEY"], !key.isEmpty {
            return .installed(version: nil)
        }
        let credPath = homeDirectory
            .appending(path: ".gemini/oauth_creds.json", directoryHint: .notDirectory)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: credPath.path, isDirectory: &isDir)
        guard exists, !isDir.boolValue,
              let data = try? Data(contentsOf: credPath), !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !json.isEmpty
        else { return .notInstalled }
        return .installed(version: nil)
    }

    // MARK: - Claude auth

    /// Claude OAuth 완료 여부 — `~/.claude/credentials.json` 가 valid JSON dict 일 때만
    /// `installed`. 단순 size>0 만으로는 corrupt/empty stub 도 통과 → false positive
    /// (must-fix /team H1).
    public func checkClaudeAuth() async -> ToolStatus {
        let credPath = homeDirectory
            .appending(path: ".claude/credentials.json", directoryHint: .notDirectory)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: credPath.path, isDirectory: &isDir)
        guard exists, !isDir.boolValue else { return .notInstalled }
        guard let data = try? Data(contentsOf: credPath), !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !json.isEmpty
        else { return .notInstalled }
        return .installed(version: nil)
    }

    // MARK: - Private helpers

    private func checkVersionedBinary(
        name: String,
        versionArgs: [String],
        minimumVersion: String?
    ) async -> ToolStatus {
        guard let path = locator.locate(name) else { return .notInstalled }
        return await checkVersionedAt(
            executable: path, args: versionArgs, minimumVersion: minimumVersion
        )
    }

    /// 이미 path 가 알려진 binary 의 버전 검사 + min version 비교.
    /// PATH lookup 외 사용자가 직접 path 알려주는 case (e.g., user-local Python bin) 용.
    private func checkVersionedAt(
        executable: URL,
        args: [String] = ["--version"],
        minimumVersion: String?
    ) async -> ToolStatus {
        let output: ProcessOutput
        do {
            output = try await executor.run(executable: executable, arguments: args)
        } catch {
            return .installed(version: nil)
        }
        let version = output.exitCode == 0
            ? (extractVersion(from: output.stdout) ?? extractVersion(from: output.stderr))
            : nil
        guard let required = minimumVersion, let v = version,
              !versionAtLeast(current: v, required: required) else {
            return .installed(version: version)
        }
        return .outdated(current: v, required: required)
    }

    /// stdout 첫 줄에서 `vX.Y.Z` 또는 `X.Y.Z` 패턴 추출.
    private func extractVersion(from text: String) -> String? {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
        // 정규식: optional v + 숫자.숫자(.숫자)?
        guard let range = firstLine.range(
            of: #"v?\d+\.\d+(\.\d+)?"#, options: .regularExpression
        ) else { return nil }
        return String(firstLine[range])
    }

    /// 간단 semver 비교 — major.minor 만 (patch 무시). v?prefix 안전.
    /// 예: `versionAtLeast(current: "v22.11.0", required: "v18")` → true.
    private func versionAtLeast(current: String, required: String) -> Bool {
        func parse(_ s: String) -> (Int, Int) {
            let trimmed = s.hasPrefix("v") ? String(s.dropFirst()) : s
            let parts = trimmed.split(separator: ".").compactMap { Int($0) }
            return (parts.first ?? 0, parts.count >= 2 ? parts[1] : 0)
        }
        let (cMaj, cMin) = parse(current)
        let (rMaj, rMin) = parse(required)
        if cMaj != rMaj { return cMaj > rMaj }
        return cMin >= rMin
    }

    private func findAiderInUserPython(under path: URL) -> URL? {
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: path, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        for versionDir in versions {
            let aider = versionDir.appending(path: "bin/aider", directoryHint: .notDirectory)
            if FileManager.default.isExecutableFile(atPath: aider.path) {
                return aider
            }
        }
        return nil
    }
}
