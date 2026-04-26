import AppKit
import MaestroCore
import SwiftUI

/// 환경설정 윈도우 — Tab 4개 (General / Agents / Shortcuts / Advanced).
struct PreferencesView: View {
    @Bindable var preferences: PreferencesStore
    let apiKeyStorage: APIKeyStorage
    let dataFolderURL: URL
    let onExportDiagnostics: @MainActor () async -> Void
    let onRequestNotificationPermission: @MainActor () async -> Void

    var body: some View {
        TabView {
            GeneralPreferencesPane(
                preferences: preferences,
                onRequestNotificationPermission: onRequestNotificationPermission
            )
            .tabItem { Label("일반", systemImage: "gearshape") }

            AgentsPreferencesPane(
                preferences: preferences,
                apiKeyStorage: apiKeyStorage
            )
            .tabItem { Label("에이전트", systemImage: "cpu") }

            ShortcutsPreferencesPane()
                .tabItem { Label("단축키", systemImage: "keyboard") }

            AdvancedPreferencesPane(
                dataFolderURL: dataFolderURL,
                onExportDiagnostics: onExportDiagnostics
            )
            .tabItem { Label("고급", systemImage: "wrench.adjustable") }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}

private struct GeneralPreferencesPane: View {
    @Bindable var preferences: PreferencesStore
    let onRequestNotificationPermission: @MainActor () async -> Void

    var body: some View {
        Form {
            Toggle("시스템 알림 사용", isOn: Binding(
                get: { preferences.snapshot.notificationsEnabled },
                set: { preferences.setNotificationsEnabled($0) }
            ))
            Toggle("로그인 시 자동 실행 (Phase 22)", isOn: Binding(
                get: { preferences.snapshot.launchAtLogin },
                set: { preferences.setLaunchAtLogin($0) }
            ))
            Stepper(value: Binding(
                get: { preferences.snapshot.dispatchTimeoutSeconds },
                set: { preferences.setDispatchTimeoutSeconds($0) }
            ), in: 5...3600, step: 5) {
                Text("디스패치 타임아웃: \(preferences.snapshot.dispatchTimeoutSeconds)초")
            }

            Button("알림 권한 다시 요청") {
                Task { await onRequestNotificationPermission() }
            }
        }
    }
}

private struct AgentsPreferencesPane: View {
    @Bindable var preferences: PreferencesStore
    let apiKeyStorage: APIKeyStorage  // 보존 — APIKeyStorage 자체는 미래 수요 대비

    private let knownAdapterIDs = ["claude", "aider"]
    @State private var actionMessage: String?

    var body: some View {
        Form {
            Picker("기본 어댑터", selection: Binding(
                get: { preferences.snapshot.preferredAdapterID ?? "claude" },
                set: { preferences.setPreferredAdapter($0) }
            )) {
                ForEach(Array(preferences.snapshot.enabledAdapterIDs).sorted(), id: \.self) { id in
                    Text(id).tag(id)
                }
            }

            Section("활성화") {
                ForEach(knownAdapterIDs, id: \.self) { id in
                    Toggle(id, isOn: Binding(
                        get: { preferences.snapshot.enabledAdapterIDs.contains(id) },
                        set: { preferences.setAdapterEnabled(id, enabled: $0) }
                    ))
                }
            }

            // I-NEW-5 fix — 기존 dead "API 키 (Keychain 저장)" 섹션 제거.
            // Maestro 는 BYOA orchestrator 라 인증을 어댑터 CLI 본인이 관리.
            // 사용자가 헷갈리지 않게 명시적 안내 + Claude 는 1-click helper 제공.
            Section("인증") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude")
                        .font(.headline)
                    Text("`claude auth login` 으로 한 번 로그인하면 OAuth 토큰이 디스크에 저장됩니다. Maestro 는 그 토큰을 그대로 활용해요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("터미널에서 Claude 로그인 열기") {
                        runInTerminal(command: "claude auth login")
                    }
                }
                .padding(.vertical, 4)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aider")
                        .font(.headline)
                    Text("API 키를 환경변수로 설정하세요. `~/.zshrc` 에 한 줄 추가하면 영구 적용:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("export ANTHROPIC_API_KEY=sk-ant-...")
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Button("터미널 열기") {
                        runInTerminal(command: "echo '# 다음 줄을 ~/.zshrc 에 붙여넣고 source ~/.zshrc 하세요'; echo 'export ANTHROPIC_API_KEY=sk-ant-...'")
                    }
                }
                .padding(.vertical, 4)
                if let actionMessage {
                    Text(actionMessage).foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    private func runInTerminal(command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        do {
            try task.run()
            actionMessage = "터미널 창이 열렸어요."
        } catch {
            actionMessage = "터미널 실행 실패: \(error.localizedDescription)"
        }
    }
}

private struct ShortcutsPreferencesPane: View {
    var body: some View {
        Form {
            Section("기본 단축키 (커스터마이징은 Phase 22 예정)") {
                shortcutRow("새 폴더 추가", keys: "⌘N")
                shortcutRow("선택 폴더 제거", keys: "⌘⌫")
                shortcutRow("커맨드 팔레트", keys: "⌘K")
                shortcutRow("폴더 1~9 전환", keys: "⌘1~⌘9")
                shortcutRow("환경설정", keys: "⌘,")
                shortcutRow("데이터 폴더 열기", keys: "⌘⇧O")
            }
        }
    }

    private func shortcutRow(_ label: String, keys: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AdvancedPreferencesPane: View {
    let dataFolderURL: URL
    let onExportDiagnostics: @MainActor () async -> Void

    var body: some View {
        Form {
            Section("데이터 위치") {
                LabeledContent("AppSupport") {
                    Text(dataFolderURL.path)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Finder 에서 열기") {
                    NSWorkspace.shared.activateFileViewerSelecting([dataFolderURL])
                }
            }
            Section("진단") {
                Button("진단 번들 내보내기…") {
                    Task { await onExportDiagnostics() }
                }
            }
        }
    }
}
