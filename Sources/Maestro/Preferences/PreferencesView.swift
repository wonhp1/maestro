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
    let apiKeyStorage: APIKeyStorage

    private let knownAdapterIDs = ["claude", "aider"]

    @State private var apiKeys: [String: String] = [:]
    @State private var loadError: String?

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

            Section("API 키 (Keychain 저장)") {
                ForEach(knownAdapterIDs, id: \.self) { id in
                    HStack {
                        Text(id).frame(width: 80, alignment: .leading)
                        SecureField("API key", text: Binding(
                            get: { apiKeys[id] ?? "" },
                            set: { newValue in
                                apiKeys[id] = newValue
                                do {
                                    try apiKeyStorage.setKey(for: id, value: newValue)
                                    loadError = nil
                                } catch {
                                    loadError = "저장 실패: \(error.localizedDescription)"
                                }
                            }
                        ))
                    }
                }
                if let loadError {
                    Text(loadError).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .task {
            for id in knownAdapterIDs {
                apiKeys[id] = (try? apiKeyStorage.key(for: id)) ?? ""
            }
        }
        .onDisappear {
            // 메모리에서 API 키 평문 제거 (must-fix /team SEC).
            // Keychain 에는 이미 저장됨. 뷰 재진입 시 .task 가 다시 로드.
            for id in apiKeys.keys {
                apiKeys[id] = ""
            }
            apiKeys.removeAll()
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
