import MaestroCore
import SwiftUI

// 폴더 등록 직전, 어떤 어댑터(vendor) 를 사용할지 사용자에게 선택받는 시트.
//
// ## UX 원칙
// - **친절** — 미설치 어댑터는 disabled + 설치 명령어 inline 표시.
// - **간결** — 라디오 + 설명 1-2 줄.
// - **빠른 결정** — 설치된 어댑터 1개뿐이면 자동 선택.
//
// (v0.9.0: codex/gemini auth banner 추가로 300 줄 초과 — 추후 ViewModel 분리.)
// swiftlint:disable:next type_body_length
struct VendorPickerSheet: View {
    let folderURL: URL
    @Bindable var folderViewModel: FolderViewModel
    @Bindable var detectionViewModel: AdapterDetectionViewModel

    @State private var selectedAdapterID: String = ""
    @State private var pendingInstallAdapterID: String?
    /// v0.8.0 — Aider 선택 시 git/python 의존성 검사 결과 캐시.
    /// nil = 아직 검사 안 됨, .checking = 진행 중, .ready(status) = 완료.
    @State private var aiderDepsState: AiderDepsState = .idle
    /// v0.9.0 — Codex / Gemini 선택 시 auth 검사 (CLI 는 설치됐지만 OAuth 안 된
    /// 경우 banner 로 안내). adapter id → auth 상태.
    @State private var authStateByAdapter: [String: AuthState] = [:]
    /// v0.9.2 — Codex 인앱 로그인 진행 중 — UI 가 spinner 표시 + 중복 실행 차단.
    @State private var codexLoginInProgress: Bool = false
    /// v0.9.2 — 인앱 로그인 결과 메시지 (성공/실패/취소).
    @State private var codexLoginMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if detectionViewModel.isDetecting {
                ProgressView("어댑터 감지 중…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                adapterList
            }

            footer
        }
        .padding(20)
        .frame(width: 560)
        .task { await loadDetections() }
        .onChange(of: selectedAdapterID) { _, newID in
            // v0.9.0 — 사용자가 codex/gemini 행 클릭하면 즉시 auth 검사 시작.
            if newID == "codex" || newID == "gemini" {
                if case .idle = authStateByAdapter[newID] ?? .idle {
                    Task { await loadAuth(for: newID) }
                }
            }
        }
        .sheet(item: Binding(
            get: { pendingInstallAdapterID.map { InstallTarget(id: $0) } },
            set: { newValue in pendingInstallAdapterID = newValue?.id }
        )) { target in
            AdapterInstallSheet(
                adapterId: target.id,
                displayName: detectionViewModel.displayName(for: target.id)
            ) { success in
                pendingInstallAdapterID = nil
                if success {
                    Task {
                        await detectionViewModel.refresh()
                        if detectionViewModel.detection(for: target.id)?.isInstalled == true {
                            selectedAdapterID = target.id
                        }
                    }
                }
            }
        }
    }

    private struct InstallTarget: Identifiable { let id: String }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("어떤 에이전트를 사용할까요?")
                .font(.title2).bold()
            Text(folderURL.path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var adapterList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(detectionViewModel.sortedAdapterIDs, id: \.self) { adapterId in
                AdapterRow(
                    adapterId: adapterId,
                    displayName: detectionViewModel.displayName(for: adapterId),
                    detection: detectionViewModel.detection(for: adapterId),
                    isSelected: selectedAdapterID == adapterId,
                    onSelect: { selectedAdapterID = adapterId },
                    onRequestInstall: { pendingInstallAdapterID = adapterId }
                )
            }
            // v0.8.0 — Aider 선택 시 git/python 의존성 inline 안내.
            if selectedAdapterID == "aider" {
                aiderDependencyBanner
            }
            // v0.9.0 — Codex / Gemini 선택 시 auth banner.
            if selectedAdapterID == "codex" || selectedAdapterID == "gemini" {
                authBanner(for: selectedAdapterID)
            }
            if detectionViewModel.sortedAdapterIDs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("어댑터를 아직 감지하지 못했어요.")
                        .foregroundStyle(.secondary)
                    Button("재시도") {
                        Task { await detectionViewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("취소", role: .cancel) {
                folderViewModel.cancelPendingAdd()
            }
            .keyboardShortcut(.cancelAction)
            Button("추가") {
                Task { await confirmAdd() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canConfirm)
        }
    }

    private func confirmAdd() async {
        do {
            let adapterId = try AdapterID.validated(rawValue: selectedAdapterID)
            await folderViewModel.confirmPendingAdd(adapterId: adapterId)
        } catch {
            folderViewModel.errorMessage = "어댑터 ID 가 잘못되었습니다: \(selectedAdapterID)"
            folderViewModel.cancelPendingAdd()
        }
    }

    private var canConfirm: Bool {
        guard !selectedAdapterID.isEmpty,
              let detection = detectionViewModel.detection(for: selectedAdapterID) else {
            return false
        }
        guard detection.isInstalled else { return false }
        // v0.8.0 — Aider 는 git + python3 도 모두 ready 여야 폴더 추가 허용.
        if selectedAdapterID == "aider" {
            if case let .ready(deps) = aiderDepsState, deps.allReady { return true }
            return false
        }
        // v0.9.0 — Codex / Gemini 는 auth 도 통과해야 폴더 추가 허용.
        if selectedAdapterID == "codex" || selectedAdapterID == "gemini" {
            if case let .ready(authed) = authStateByAdapter[selectedAdapterID] ?? .idle, authed {
                return true
            }
            return false
        }
        return true
    }

    private func loadDetections() async {
        await detectionViewModel.refresh()
        // 첫 진입 시 첫 설치된 어댑터 자동 선택 — 친절 UX.
        if selectedAdapterID.isEmpty,
           let firstInstalled = detectionViewModel.sortedAdapterIDs.first(where: {
               detectionViewModel.detection(for: $0)?.isInstalled == true
           }) {
            selectedAdapterID = firstInstalled
        }
        // 첫 선택이 aider 면 의존성 미리 점검.
        if selectedAdapterID == "aider", case .idle = aiderDepsState {
            await loadAiderDeps()
        }
        // v0.9.0 — codex/gemini 는 auth 미리 점검.
        if selectedAdapterID == "codex" || selectedAdapterID == "gemini" {
            await loadAuth(for: selectedAdapterID)
        }
    }

    /// v0.9.0 — Codex / Gemini 인증 상태 검사.
    private func loadAuth(for adapterId: String) async {
        authStateByAdapter[adapterId] = .checking
        let checker = EnvironmentChecker()
        let isAuthed: Bool
        switch adapterId {
        case "codex":
            isAuthed = await checker.checkCodexAuth().isReady
        case "gemini":
            isAuthed = await checker.checkGeminiAuth().isReady
        default:
            isAuthed = true
        }
        authStateByAdapter[adapterId] = .ready(isAuthed)
    }

    @ViewBuilder
    private func authBanner(for adapterId: String) -> some View {
        let state = authStateByAdapter[adapterId] ?? .idle
        switch state {
        case .idle:
            Color.clear.frame(height: 0)
                .task { await loadAuth(for: adapterId) }
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("인증 상태 확인 중…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ready(let authed):
            if authed {
                EmptyView()
            } else {
                authMissingBanner(for: adapterId)
            }
        }
    }

    @ViewBuilder
    private func authMissingBanner(for adapterId: String) -> some View {
        let cliName = adapterId == "codex" ? "Codex" : "Gemini"
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(cliName) 인증이 필요합니다")
                    .font(.callout).bold()
            }
            // v0.9.2 — 인앱 로그인 (Codex 만 — Gemini 는 별도 login 명령 X).
            if adapterId == "codex" {
                Text("아래 \"Maestro 로 로그인\" 클릭 시 브라우저가 자동으로 열립니다. 로그인 완료까지 기다린 후 자동 갱신.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button {
                        Task { await performCodexLogin() }
                    } label: {
                        if codexLoginInProgress {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("로그인 진행 중…")
                            }
                        } else {
                            Label("Maestro 로 로그인", systemImage: "person.badge.key.fill")
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(codexLoginInProgress)
                    Button("다시 검사") { Task { await loadAuth(for: adapterId) } }
                        .controlSize(.small)
                        .disabled(codexLoginInProgress)
                }
                if let msg = codexLoginMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("또는 터미널에서 `codex login` 실행 / OPENAI_API_KEY 환경변수 설정")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                // Gemini — 별도 auth 명령 없음, 첫 prompt 호출 시 자동 OAuth.
                Text("터미널에서 `gemini` 를 실행하면 첫 사용 시 브라우저로 Google OAuth 진행됩니다. 또는 GEMINI_API_KEY 환경변수.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("다시 검사") { Task { await loadAuth(for: adapterId) } }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// v0.9.2 — codex login 인앱 실행 → polling → 자동 갱신.
    private func performCodexLogin() async {
        guard let codexPath = PATHExecutableLocator().locate("codex") else {
            codexLoginMessage = "codex CLI 를 찾을 수 없어요"
            return
        }
        codexLoginInProgress = true
        codexLoginMessage = "브라우저에서 로그인 중…"
        defer { codexLoginInProgress = false }

        let result = await InteractiveAuthHelper.loginCodex(codexPath: codexPath)
        switch result {
        case .success:
            codexLoginMessage = "로그인 성공"
            await loadAuth(for: "codex")
        case .cancelled:
            codexLoginMessage = "로그인 취소됨"
        case .timedOut:
            codexLoginMessage = "5분 내 로그인 안 됨. 다시 시도해주세요."
        case .processFailed(let message):
            codexLoginMessage = "실패: \(message)"
        }
    }

    /// v0.9.0 — Codex / Gemini auth 검사 진행 상태.
    private enum AuthState: Equatable {
        case idle
        case checking
        case ready(Bool)
    }

    /// v0.8.0 — Aider 의존성 (git, python3) 검사. selectedAdapterID 가 aider 일 때만 호출.
    private func loadAiderDeps() async {
        aiderDepsState = .checking
        let checker = EnvironmentChecker()
        async let git = checker.checkGit()
        async let py = checker.checkPython3()
        let result = AiderDeps(git: await git, python3: await py)
        aiderDepsState = .ready(result)
    }

    @ViewBuilder
    private var aiderDependencyBanner: some View {
        switch aiderDepsState {
        case .idle:
            Color.clear.frame(height: 0)
                .task { await loadAiderDeps() }
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Aider 의존성 (git, python3) 검사 중…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ready(let deps):
            if deps.allReady {
                EmptyView()
            } else {
                aiderDepsWarning(deps)
            }
        }
    }

    @ViewBuilder
    private func aiderDepsWarning(_ deps: AiderDeps) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Aider 사용에 필요한 도구가 누락됐습니다")
                    .font(.callout).bold()
            }
            if !deps.git.isReady {
                HStack(spacing: 8) {
                    Text("• git").font(.caption)
                    Button {
                        if let url = URL(string: "https://git-scm.com/download/mac") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("git 다운로드 페이지 열기", systemImage: "arrow.up.forward.app")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    Button("다시 검사") { Task { await loadAiderDeps() } }
                        .controlSize(.small)
                }
            }
            if !deps.python3.isReady {
                Text("• python3 \(versionLabel(deps.python3)) — Aider 는 python 3.10+ 필요. 시스템 업데이트 또는 Homebrew 사용 권장.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func versionLabel(_ status: ToolStatus) -> String {
        switch status {
        case .installed(let version?):
            return "(v\(version))"
        case .installed(nil):
            return "(설치됨)"
        case .outdated(let current, let required):
            return "(현재 \(current), \(required) 이상 필요)"
        case .notInstalled:
            return "(미설치)"
        }
    }

    /// Aider 의존성 검사 진행 상태.
    private enum AiderDepsState: Equatable {
        case idle
        case checking
        case ready(AiderDeps)
    }

    /// Aider 가 필요로 하는 git + python3 도구의 상태.
    private struct AiderDeps: Equatable {
        let git: ToolStatus
        let python3: ToolStatus
        var allReady: Bool { git.isReady && python3.isReady }
    }
}

/// 한 어댑터의 한 행 — 라디오 + 이름 + 상태 (✓ 버전 / ✗ 미설치 + 설치 안내).
private struct AdapterRow: View {
    let adapterId: String
    let displayName: String
    let detection: AdapterDetection?
    let isSelected: Bool
    let onSelect: () -> Void
    let onRequestInstall: () -> Void

    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: .top, spacing: 12) {
                radio
                content
                Spacer()
            }
            .padding(12)
            .background(rowBackground)
            .overlay(rowBorder)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInstalled)
        .opacity(isInstalled ? 1.0 : 0.65)
    }

    private var radio: some View {
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .imageScale(.large)
            .padding(.top, 2)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(displayName)
                    .font(.body).bold()
                if let badge = AdapterDetectionViewModel.recommendationBadge(for: adapterId) {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                Spacer()
                if isInstalled {
                    Label(versionBadge, systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("미설치", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if let desc = AdapterDetectionViewModel.description(for: adapterId) {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !isInstalled, let hint = AdapterDetectionViewModel.installationHint(for: adapterId) {
                installationHint(hint)
            }
        }
    }

    @ViewBuilder
    private func installationHint(_ hint: InstallationHint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hint.description).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("자동 설치") { onRequestInstall() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                Text(hint.command)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if let url = hint.docsURL {
                    Link("도움말 →", destination: url)
                        .font(.caption)
                }
            }
        }
        .padding(.top, 2)
    }

    private var isInstalled: Bool { detection?.isInstalled == true }

    private var versionBadge: String {
        if let version = detection?.version, !version.isEmpty {
            return "v\(version)"
        }
        return "설치됨"
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.10)
        } else {
            Color.clear
        }
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                lineWidth: isSelected ? 1.5 : 1
            )
    }

    private func handleTap() {
        guard isInstalled else { return }
        onSelect()
    }
}
