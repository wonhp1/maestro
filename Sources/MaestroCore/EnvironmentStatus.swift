import Foundation

/// v0.8.0 — 환경 도구 (Node, Claude, git 등) 의 검사 결과.
///
/// 세 케이스로 표현:
/// - `installed(version)` — 설치됨. version 은 추출 실패 시 nil.
/// - `outdated(current, required)` — 설치됐지만 최소 요구 버전 미만.
/// - `notInstalled` — PATH 에서 못 찾음.
public enum ToolStatus: Sendable, Equatable, Codable {
    case installed(version: String?)
    case outdated(current: String, required: String)
    case notInstalled

    /// 사용 가능 여부 — installed 만 true. !isReady 가 "자동 설치 또는 업그레이드 필요".
    public var isReady: Bool {
        if case .installed = self { return true }
        return false
    }
}

/// v0.8.0 — 환경 검사 결과 묶음. EnvironmentChecker.checkAll() 반환.
///
/// 도구별 status:
/// - `node` — Node.js (Claude Code 의 npm 의존)
/// - `claude` — Claude Code CLI
/// - `git` — Aider 의 자동 commit 의존 (사용자가 git repo 폴더 작업 시도 필수)
/// - `python3` — Aider 가 pip 로 설치되므로
/// - `aider` — Aider CLI
/// - `claudeAuth` — `~/.claude/credentials.json` 존재 여부 (OAuth 완료 표시)
public struct EnvironmentStatus: Sendable, Equatable {
    public let node: ToolStatus
    public let claude: ToolStatus
    public let git: ToolStatus
    public let python3: ToolStatus
    public let aider: ToolStatus
    public let claudeAuth: ToolStatus

    public init(
        node: ToolStatus,
        claude: ToolStatus,
        git: ToolStatus,
        python3: ToolStatus,
        aider: ToolStatus,
        claudeAuth: ToolStatus
    ) {
        self.node = node
        self.claude = claude
        self.git = git
        self.python3 = python3
        self.aider = aider
        self.claudeAuth = claudeAuth
    }

    /// Claude Code 사용에 필수 도구가 모두 준비됐는지.
    public var claudeReady: Bool {
        node.isReady && claude.isReady && claudeAuth.isReady
    }

    /// Aider 사용에 필수 도구가 모두 준비됐는지.
    public var aiderReady: Bool {
        git.isReady && python3.isReady && aider.isReady
    }
}

/// 어댑터별 dependency mapping. UI 가 어댑터 선택에 따른 누락 도구 안내에 사용.
public enum AdapterRequirement {
    /// Claude Code 가 동작하려면 필요한 도구.
    public static let claude: [Tool] = [.node, .claude, .claudeAuth]
    /// Aider 가 동작하려면 필요한 도구.
    public static let aider: [Tool] = [.git, .python3, .aider]

    public enum Tool: Sendable, Equatable, Hashable {
        case node, claude, git, python3, aider, claudeAuth
    }
}
