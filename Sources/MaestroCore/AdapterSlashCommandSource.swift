import Foundation

/// v0.7.0 Phase 3 — 어댑터가 실시간 capture 한 SDK builtin 슬래시 명령을
/// `SlashCommandSource` 로 노출.
///
/// ## 배경
/// Claude SDK 모드 (`claude -p`) 에서 동작 가능한 builtin (`/compact`, `/usage` 등)
/// 은 Maestro 가 hardcoded 로 알 수 없음. 매 dispatch 의 첫 응답
/// `system.init.slash_commands` 배열에 정확한 list 가 옴 — 이를 ClaudeAdapter 가
/// `capturedSlashCommands()` 로 노출. 이 source 가 그걸 popover/팔레트 에 노출.
///
/// ## 동작
/// - `discover()` 호출 시 어댑터의 capturedSlashCommands() async 호출
/// - 결과를 `DiscoveredSlashCommand(.builtin)` 으로 wrap
/// - 빈 배열이면 — 첫 dispatch 전이라 — 자연스럽게 popover 에 안 보임
/// - 첫 dispatch 후 capture 가 채워지면 자동으로 노출됨
///
/// ## 어댑터 무관
/// AgentAdapter 프로토콜의 `capturedSlashCommands()` 를 호출하므로 ClaudeAdapter
/// 외에 다른 어댑터 (Aider 등) 가 capture 인프라 추가 시 자동 동작.
public struct AdapterSlashCommandSource: SlashCommandSource {
    public let adapter: any AgentAdapter

    public init(adapter: any AgentAdapter) {
        self.adapter = adapter
    }

    public func discover() async -> [DiscoveredSlashCommand] {
        let names = await adapter.capturedSlashCommands()
        return names.map { name in
            DiscoveredSlashCommand(
                command: SlashCommand(
                    name: name,
                    description: "",  // popover 가 source label 로 출처 표시
                    category: "builtin"
                ),
                source: .builtin,
                filePath: nil
            )
        }
    }
}
