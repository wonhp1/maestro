import MaestroCore
import SwiftUI

/// v0.8.0 — 온보딩의 environment 검사 단계 view.
///
/// 검사 결과 list (✓/⚠️/✗) + 자동 설치 버튼 + git 외부 링크 + 다시 검사.
struct EnvironmentSetupSheet: View {
    @Bindable var viewModel: EnvironmentSetupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.phase {
            case .idle, .scanning:
                scanningView
            case .ready(let status):
                readyView(status: status)
            case .installing(let progress):
                installingView(progress: progress)
            }
            if let error = viewModel.lastError {
                errorBanner(error)
            }
        }
        .task { if case .idle = viewModel.phase { await viewModel.scan() } }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var scanningView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("환경 도구 검사 중…")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func readyView(status: EnvironmentStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(label: "Node.js", status: status.node)
            statusRow(label: "Claude Code", status: status.claude)
            statusRow(label: "Anthropic 로그인", status: status.claudeAuth)
            statusRow(label: "git (선택)", status: status.git, optional: true)
        }
        .font(.callout)

        if !status.claudeReady {
            actionButtons(status: status)
        } else {
            Label("Claude 사용에 필요한 환경이 준비됐습니다", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
        }
    }

    @ViewBuilder
    private func actionButtons(status: EnvironmentStatus) -> some View {
        HStack(spacing: 8) {
            if !status.node.isReady || !status.claude.isReady {
                Button {
                    Task { await viewModel.installMissing() }
                } label: {
                    Label("환경 자동 설치", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .help("Node.js 와 Claude Code 를 자동으로 설치합니다. 관리자 비밀번호가 필요합니다.")
            }
            if status.node.isReady, status.claude.isReady, !status.claudeAuth.isReady {
                claudeAuthGuide
            }
            if !status.git.isReady {
                Button {
                    viewModel.openGitDownloadPage()
                } label: {
                    Label("git 다운로드", systemImage: "arrow.up.forward.app")
                }
                .help("git 은 Aider 사용 시 필요합니다. 공식 페이지에서 .pkg 받아 설치 후 다시 검사하세요.")
            }
            Button {
                Task { await viewModel.rescan() }
            } label: {
                Label("다시 검사", systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var claudeAuthGuide: some View {
        Text("터미널에서 `claude` 를 실행해 Anthropic 계정으로 로그인하세요.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func installingView(progress: InstallProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progressLabel(progress))
                    .foregroundStyle(.secondary)
            }
            // sudo 안내는 Node 설치 phase 에서만 — Claude/Aider 는 user-level.
            if needsSudoHint(progress) {
                Text("관리자 인증 창이 뜨면 비밀번호를 입력해주세요. (Touch ID 가능)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Node 설치 단계에서만 sudo 안내 표시 — 다른 phase 는 user-level.
    private func needsSudoHint(_ progress: InstallProgress) -> Bool {
        if case let .running(phase) = progress {
            return phase.contains("Node.js")
        }
        return false
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func statusRow(label: String, status: ToolStatus, optional: Bool = false) -> some View {
        HStack(spacing: 8) {
            statusIcon(status: status, optional: optional)
            Text(label)
            if case let .installed(version?) = status {
                Text(version)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            if case let .outdated(current, required) = status {
                Text("\(current) → \(required)+ 필요")
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func statusIcon(status: ToolStatus, optional: Bool) -> some View {
        switch status {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("설치됨")
        case .outdated:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("업데이트 필요")
        case .notInstalled:
            Image(systemName: optional
                  ? "questionmark.circle"
                  : "xmark.circle.fill")
                .foregroundStyle(optional ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                .accessibilityLabel(optional ? "선택사항 — 설치 안됨" : "설치 안됨")
        }
    }

    private func progressLabel(_ progress: InstallProgress) -> String {
        switch progress {
        case .downloading(let bytes, let total):
            if let total, total > 0 {
                let percent = Int(Double(bytes) / Double(total) * 100)
                return "다운로드 중… \(percent)%"
            }
            let mb = Double(bytes) / 1_000_000
            return String(format: "다운로드 중… %.1f MB", mb)
        case .running(let phase):
            return phase
        case .complete:
            return "완료"
        }
    }
}
