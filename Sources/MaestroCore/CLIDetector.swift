import Foundation

/// CLI 어댑터의 **설치 여부 + 버전** 을 자동 감지하는 유틸.
///
/// 두 단계:
/// 1. `ExecutableLocating` 으로 PATH 에서 실행 파일 찾기
/// 2. 찾으면 `ProcessExecuting` 으로 `executable + detectArgs` 실행 → stdout 수집
/// 3. `versionRegex` 로 버전 추출 (실패해도 `isInstalled=true` 유지, version=nil)
///
/// throws 하지 않으며, 어떤 실패든 `notInstalled` 또는 version=nil 로 표현.
public struct CLIDetector: Sendable {
    private let locator: any ExecutableLocating
    private let executor: any ProcessExecuting

    public init(
        locator: any ExecutableLocating = PATHExecutableLocator(),
        executor: any ProcessExecuting = DefaultProcessExecutor()
    ) {
        self.locator = locator
        self.executor = executor
    }

    /// 어댑터 프로파일 기반 감지. `AgentProfile` 의 `executable` / `detectArgs` /
    /// `versionRegex` 를 사용. 결과는 `AdapterDetection`.
    public func detect(profile: AgentProfile) async -> AdapterDetection {
        let now = Date()
        guard let path = locator.locate(profile.executable) else {
            return AdapterDetection.notInstalled(at: now)
        }
        let output: ProcessOutput
        do {
            output = try await executor.run(executable: path, arguments: profile.detectArgs)
        } catch {
            // 실행 실패 → 설치는 됐지만 동작 불가. version=nil.
            return AdapterDetection(
                isInstalled: true,
                version: nil,
                executablePath: path,
                detectedAt: now
            )
        }
        // ReDoS 방어 (Phase 4 must-fix): regex 입력을 첫 16 KiB 로 truncate.
        // --version 출력은 보통 < 1 KiB. 한도 초과 시 이미 비정상 출력이라 추가 매칭 시도 무의미.
        let combined = Self.truncate(output.stdout, max: Self.maxRegexInputBytes)
            + "\n"
            + Self.truncate(output.stderr, max: Self.maxRegexInputBytes)
        let version = Self.extractVersion(from: combined, pattern: profile.versionRegex)
        return AdapterDetection(
            isInstalled: true,
            version: version,
            executablePath: path,
            detectedAt: now
        )
    }

    /// regex 입력 cap (Phase 4 must-fix). detect 출력이 이 한도를 넘기면 앞부분만 사용.
    static let maxRegexInputBytes: Int = 16 * 1024

    private static func truncate(_ s: String, max: Int) -> String {
        guard s.utf8.count > max else { return s }
        let prefixUTF8 = s.utf8.prefix(max)
        return String(decoding: prefixUTF8, as: UTF8.self)
    }

    /// 정규식으로 버전 문자열 추출. 첫 캡처 그룹이 있으면 그것을, 없으면 전체 매치.
    /// 실패하면 nil.
    static func extractVersion(from text: String, pattern: String) -> String? {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        // 캡처 그룹 1 우선, 없으면 전체 매치.
        let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard captureRange.location != NSNotFound,
              let swiftRange = Range(captureRange, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }
}
