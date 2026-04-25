import Foundation

/// 자식 프로세스에 전달할 환경 변수에서 **시크릿/OAuth 토큰** 을 제거.
///
/// ## 동기
/// 부모 프로세스의 환경에는 보통 다양한 시크릿이 있다 (Anthropic/OpenAI/AWS/...).
/// 자식이 임의의 코드를 실행할 수 있는 CLI (Claude / Aider) 라면, 부모의 토큰을
/// 상속받는 것은 **횡적 권한 상승 위험**. 자식이 자체 인증 (config 파일 / Keychain)
/// 으로만 동작하도록 부모 토큰을 제거.
///
/// ## 디자인 — Default vs Strict
/// - **`.default` (deny-list)**: 알려진 시크릿 키 + 패턴 차단. PATH/HOME 등 자식이 동작
///   하는 데 필요한 변수는 보존.
/// - **`.strict` (allow-list)**: 시스템 변수만 허용, 모든 사용자 변수 차단. 신뢰할 수
///   없는 어댑터 또는 격리된 실행 시 권장.
///
/// ## 매칭 규칙 (대소문자 무시)
/// - `denyKeys`: 정확히 일치하는 키
/// - `denyPrefixes`: 키가 이 prefix 로 시작
/// - `denySuffixes`: 키가 이 suffix 로 끝남 (`_API_KEY`, `_TOKEN`, `_SECRET` 등)
public struct EnvironmentSanitizer: Sendable {
    public let denyKeys: Set<String>
    public let denyPrefixes: [String]
    public let denySuffixes: [String]
    /// allow-list 모드 — 비어있지 않으면 이 set 에 *없는* 모든 키 차단. deny rules 무시.
    public let allowKeysOnly: Set<String>?

    public init(
        denyKeys: Set<String> = [],
        denyPrefixes: [String] = [],
        denySuffixes: [String] = [],
        allowKeysOnly: Set<String>? = nil
    ) {
        self.denyKeys = Set(denyKeys.map { $0.uppercased() })
        self.denyPrefixes = denyPrefixes.map { $0.uppercased() }
        self.denySuffixes = denySuffixes.map { $0.uppercased() }
        self.allowKeysOnly = allowKeysOnly.map { Set($0.map { $0.uppercased() }) }
    }

    /// Maestro 표준 deny-list. 알려진 LLM/클라우드/CI/패키지 매니저 시크릿 패턴.
    public static let `default` = EnvironmentSanitizer(
        denyKeys: [
            // Anthropic
            "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
            // OpenAI
            "OPENAI_API_KEY", "OPENAI_ORGANIZATION",
            // 기타 LLM 제공자
            "HF_TOKEN", "HUGGINGFACE_TOKEN", "COHERE_API_KEY", "MISTRAL_API_KEY",
            "REPLICATE_API_TOKEN", "GROQ_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY",
            "PERPLEXITY_API_KEY", "TOGETHER_API_KEY", "DEEPSEEK_API_KEY",
            "XAI_API_KEY", "FIREWORKS_API_KEY", "KAGI_API_KEY", "BRAVE_API_KEY",
            // VCS / CI / 호스팅
            "GITHUB_TOKEN", "GH_TOKEN", "GITLAB_TOKEN", "GITLAB_PRIVATE_TOKEN",
            "CIRCLECI_TOKEN", "VERCEL_TOKEN", "NETLIFY_AUTH_TOKEN",
            "CF_API_TOKEN", "CLOUDFLARE_API_TOKEN",
            // 패키지 매니저
            "NPM_TOKEN", "NPM_CONFIG_AUTH",
            // 클라우드
            "GOOGLE_APPLICATION_CREDENTIALS", "AZURE_CLIENT_SECRET",
            "DOCKER_PASSWORD",
            // 측방 이동
            "SSH_AUTH_SOCK", "KUBECONFIG",
        ],
        denyPrefixes: [
            "AWS_",                  // AWS family
            "NPM_CONFIG_AUTH",
            "CURSOR_TOKEN_",
            "AIDER_API_KEY_",
        ],
        denySuffixes: [
            // Generic suffixes — 새 서비스 키 자동 차단.
            "_API_KEY", "_TOKEN", "_SECRET", "_PASSWORD", "_PASSWD",
            "_AUTH", "_CREDENTIALS", "_BASE_URL", "_PROXY", "_ENDPOINT",
        ]
    )

    /// **Strict** — 시스템 변수만 허용. 모든 사용자 변수 차단.
    /// 신뢰할 수 없는 어댑터 / 격리 실행 시 권장.
    public static let strict = EnvironmentSanitizer(
        allowKeysOnly: [
            "PATH", "HOME", "USER", "LOGNAME", "SHELL",
            "LANG", "LC_ALL", "LC_CTYPE", "TZ", "TERM", "TMPDIR",
        ]
    )

    public func sanitize(_ environment: [String: String]) -> [String: String] {
        environment.filter { key, _ in !shouldDeny(key: key) }
    }

    public func sanitizedProcessEnvironment() -> [String: String] {
        sanitize(ProcessInfo.processInfo.environment)
    }

    /// 단일 키 차단 여부 — 모든 매칭은 대소문자 무시.
    public func shouldDeny(key: String) -> Bool {
        let upper = key.uppercased()
        if let allow = allowKeysOnly { return !allow.contains(upper) }
        if denyKeys.contains(upper) { return true }
        for prefix in denyPrefixes where upper.hasPrefix(prefix) { return true }
        for suffix in denySuffixes where upper.hasSuffix(suffix) { return true }
        return false
    }
}
