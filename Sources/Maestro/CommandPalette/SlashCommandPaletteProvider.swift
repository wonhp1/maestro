import MaestroCore

/// 발견된 슬래시 명령을 커맨드 팔레트의 `Command` 로 변환.
///
/// `onSelect` 는 사용자가 항목을 실행했을 때 호출 — 호출자(ControlTowerEnvironment)
/// 가 dispatch / 입력 보조 / 외부 처리를 결정.
///
/// `commands()` 는 호출 시점에 registry snapshot — registry 가 캐시 + observe 책임.
struct SlashCommandPaletteProvider: CommandProvider {
    let registry: SlashCommandRegistry
    let onSelect: @MainActor @Sendable (DiscoveredSlashCommand) async -> Void

    func commands() async -> [Command] {
        let discovered = await registry.snapshot()
        return discovered.map { item in
            // 외부 .md 파일에서 온 텍스트 — bidi/ZW/control char sanitize (must-fix /team SEC).
            let safeName = DisplayTextSanitizer.sanitize(item.command.name)
            let safeDesc = DisplayTextSanitizer.sanitize(item.command.description)
            let argHint = item.command.arguments?.first
                .map(DisplayTextSanitizer.sanitize)
            let title = "/\(safeName)"
            let subtitle: String? = safeDesc.isEmpty ? item.source.displayLabel : safeDesc
            return Command(
                id: "slash:\(item.id)",
                title: title,
                subtitle: subtitle,
                category: .slash,
                shortcutHint: argHint,
                handler: { await onSelect(item) }
            )
        }
    }
}
