import AppKit
import Foundation
import Observation

/// v0.8.0 — 온보딩 detectAgents 단계의 driving state.
///
/// 환경 검사 → 누락 도구 표시 → 자동 설치 → progress → 다시 검사 흐름 관리.
///
/// ## 상태 머신
/// ```
/// idle ──[scan]──→ scanning ──→ ready(status)
///                                    │
///                                    │ [installAll] (누락 있을 때만)
///                                    ▼
///                                installing(progress) ──→ ready(updated status)
///                                    │
///                                    │ [error]
///                                    ▼
///                                ready(status) + lastError
/// ```
@MainActor
@Observable
public final class EnvironmentSetupViewModel {
    public enum Phase: Equatable {
        case idle
        case scanning
        case ready(EnvironmentStatus)
        case installing(InstallProgress)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lastError: String?

    @ObservationIgnored
    private let checker: EnvironmentChecker
    @ObservationIgnored
    private let installer: EnvironmentInstaller
    /// 외부 (OnboardingView) 가 EnvironmentStatus 변경을 받아 다른 VM 과 동기화할 때 사용.
    /// `onChange` view-driven side effect 대신 VM 이 직접 알림 — aider 단독 변경 등 모든
    /// status 변화를 놓치지 않음.
    @ObservationIgnored
    public var onStatusChange: (@MainActor @Sendable (EnvironmentStatus) -> Void)?

    public init(
        checker: EnvironmentChecker = EnvironmentChecker(),
        installer: EnvironmentInstaller = EnvironmentInstaller()
    ) {
        self.checker = checker
        self.installer = installer
    }

    /// 사용 가능한 status (있을 때).
    public var status: EnvironmentStatus? {
        if case let .ready(s) = phase { return s }
        return nil
    }

    /// Claude 사용에 필수 도구 누락 여부 (Node + Claude + claude-auth).
    public var missingClaudeRequirements: Bool {
        guard let s = status else { return true }
        return !s.claudeReady
    }

    /// 자동 설치 가능 도구 (Node, Claude, Codex, Gemini) 중 누락된 게 있는지.
    /// v0.9.0: Codex / Gemini 도 포함 — 사용자가 "환경 자동 설치" 버튼으로 모두 설치.
    public var hasInstallableMissing: Bool {
        guard let s = status else { return false }
        return !s.node.isReady || !s.claude.isReady
            || !s.codex.isReady || !s.gemini.isReady
    }

    /// 환경 검사 시작. 결과를 phase 에 반영. lastError 는 의도적으로 보존 — install 실패
    /// 후 자동 rescan 호출 시 사용자에게 에러 메시지가 사라지지 않도록.
    public func scan() async {
        phase = .scanning
        let result = await checker.checkAll()
        phase = .ready(result)
        onStatusChange?(result)
    }

    /// 누락된 install 가능 도구 자동 설치. 호출 후 자동 재검사.
    /// v0.9.0 변경: Node + Claude + Codex + Gemini 모두 설치 (전부 npm 글로벌, sudo
    /// 한 번 + 사용자가 한 번 클릭으로 4개 어댑터 환경 완성).
    /// - Parameter includeAider: Aider 도 함께 설치할지 (default false — pip3 권한
    ///   별도 + 정책상 선택). Codex/Gemini 는 npm 이라 default true 와 동일 동작.
    public func installMissing(includeAider: Bool = false) async {
        // 평탄화 — guard fall-through.
        if case .idle = phase {
            await scan()
        }
        guard case let .ready(initial) = phase else { return }
        lastError = nil

        do {
            if !initial.node.isReady {
                try await runInstallStage { try await installer.installNode(progress: $0) }
            }
            // Node 설치 후 재검사 — npm path 갱신 반영.
            let afterNode = await checker.checkAll()
            if !afterNode.claude.isReady {
                try await runInstallStage { try await installer.installClaude(progress: $0) }
            }
            // v0.9.0 — Codex / Gemini 도 default 로 함께 설치 (사용자 기대 부합).
            if !afterNode.codex.isReady {
                try await runInstallStage { try await installer.installCodex(progress: $0) }
            }
            if !afterNode.gemini.isReady {
                try await runInstallStage { try await installer.installGemini(progress: $0) }
            }
            if includeAider, !afterNode.aider.isReady {
                try await runInstallStage { try await installer.installAider(progress: $0) }
            }
        } catch let err as EnvironmentInstallerError {
            lastError = humanizeError(err)
        } catch {
            lastError = "설치 실패: \(error.localizedDescription)"
        }
        // 끝에 무조건 재검사 — 부분 성공 케이스 반영.
        await scan()
    }

    /// 외부에서 git 설치 후 사용자가 다시 검사 클릭. 사용자 트리거 wrapper —
    /// 명시적 user action 이므로 stale lastError 도 함께 정리.
    public func rescan() async {
        lastError = nil
        await scan()
    }

    /// v0.9.0 — Codex CLI 단독 설치 (Claude 와 별개).
    public func installCodex() async {
        lastError = nil
        do {
            try await runInstallStage { try await installer.installCodex(progress: $0) }
        } catch let err as EnvironmentInstallerError {
            lastError = humanizeError(err)
        } catch {
            lastError = "Codex 설치 실패: \(error.localizedDescription)"
        }
        await scan()
    }

    /// v0.9.0 — Gemini CLI 단독 설치 (Claude 와 별개).
    public func installGemini() async {
        lastError = nil
        do {
            try await runInstallStage { try await installer.installGemini(progress: $0) }
        } catch let err as EnvironmentInstallerError {
            lastError = humanizeError(err)
        } catch {
            lastError = "Gemini 설치 실패: \(error.localizedDescription)"
        }
        await scan()
    }

    /// git 다운로드 페이지 열기 — 자동 설치 X (외부 링크).
    public func openGitDownloadPage() {
        let url = URL(string: "https://git-scm.com/download/mac")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    /// install actor 호출 + progress 콜백 → phase 갱신 bridge.
    /// progress 가 백그라운드에서 호출돼도 MainActor 위에서 동기적으로 phase 를 set 해
    /// `Task` spawn race (downloading → complete → downloading 역행) 를 차단.
    private func runInstallStage(
        _ work: (@Sendable @escaping (InstallProgress) -> Void) async throws -> Void
    ) async throws {
        try await work { [weak self] event in
            // MainActor 위에서 호출되면 즉시 동기적으로, 아니면 dispatch 후 적용.
            // 직렬 적용 보장 — 매 이벤트가 spawn 되는 Task 간 순서 비결정성을 회피.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.phase = .installing(event) }
            } else {
                DispatchQueue.main.async { self?.phase = .installing(event) }
            }
        }
    }

    private func humanizeError(_ err: EnvironmentInstallerError) -> String {
        switch err {
        case .sudoCancelled:
            return "관리자 인증이 취소되었습니다. 다시 시도하시려면 '환경 자동 설치' 버튼을 눌러주세요."
        case .sudoFailed(let reason):
            return "인증 실패: \(reason)"
        case .downloadFailed(let reason):
            return "다운로드 실패: \(reason)"
        case .installFailed(let exitCode, let stderr):
            return "설치 실패 (exit \(exitCode)): \(stderr.suffix(200))"
        }
    }
}
