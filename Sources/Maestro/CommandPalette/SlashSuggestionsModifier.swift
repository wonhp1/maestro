import AppKit
import MaestroCore
import SwiftUI

/// v0.7.0 Phase 2 — 입력창의 `/` 자동완성 popover 부착.
///
/// 사용법:
/// ```swift
/// TextEditor(text: $draft)
///     .modifier(SlashSuggestionsModifier(
///         draft: $draft,
///         registry: env.slashCommandRegistry
///     ))
/// ```
///
/// ## 동작
/// - `draft` onChange → SlashSuggestionEngine.evaluate → suggestion 갱신
/// - suggestion != nil → `.popover` 자동 표시
/// - `.onKeyPress(.upArrow / .downArrow)` → selectedIndex 이동 (wrap-around)
/// - `.onKeyPress(.return)` → applySelection → draft 갱신, popover 닫힘
/// - `.onKeyPress(.escape)` → popover 닫힘 (draft 변경 X)
///
/// ## 동시성
/// registry 는 actor — snapshot 호출은 `.task(id: draft)` 안에서 await.
/// debounce 80ms 로 typing burst 흡수 (Cancel-then-restart 패턴).
struct SlashSuggestionsModifier: ViewModifier {
    @Binding var draft: String
    let registry: SlashCommandRegistry

    @State private var snapshot: [DiscoveredSlashCommand] = []
    @State private var suggestion: SlashSuggestionEngine.Suggestion?
    @State private var selectedIndex: Int = 0
    /// applySelection 직후 draft 가 변경 → .task 재실행 → 새 popover 가 또 뜨는
    /// re-trigger 차단 (must-fix /team MED). 사용자가 다시 한 글자 타이핑할 때까지 latch.
    @State private var lastAppliedDraft: String = ""
    /// v0.7.0 Phase 2 fix — TextEditor/TextField 가 화살표를 cursor 이동에 흡수해
    /// SwiftUI .onKeyPress 까지 안 옴. NSEvent local monitor 로 popover 가 떴을 때만
    /// 가로챔. dismiss 시 해제.
    @State private var keyMonitor: KeyMonitorBox = KeyMonitorBox()

    /// pure logic — view rebuild 마다 새로 만들어도 비용 없음 (struct, no state).
    private let engine = SlashSuggestionEngine()

    func body(content: Content) -> some View {
        content
            .task(id: draft) {
                // applySelection latch — 직후 같은 draft 면 skip.
                if draft == lastAppliedDraft { return }
                // typing burst — debounce 80ms.
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled else { return }
                // captured draft (must-fix /team HIGH-1) — snapshot await 중 draft 변하면
                // 다음 task 가 cancel 시켜야 정확. 여기서 한 번 더 snapshot.
                let captured = draft
                snapshot = await registry.snapshot()
                guard !Task.isCancelled else { return }
                // captured 와 현재 draft 가 다르면 더 최신 task 가 진행 중 — 이 결과 버림.
                guard captured == draft else { return }
                let new = engine.evaluate(draft: captured, registrySnapshot: snapshot)
                suggestion = new
                selectedIndex = 0  // 새 suggestion 마다 첫 항목으로 reset
            }
            .popover(
                isPresented: Binding(
                    get: { suggestion != nil },
                    set: { isShown in
                        if !isShown { suggestion = nil }
                    }
                ),
                attachmentAnchor: .point(.bottomLeading),
                arrowEdge: .top
            ) {
                if let suggestion {
                    SlashPopoverContent(
                        candidates: suggestion.candidates,
                        selectedIndex: selectedIndex,
                        onSelect: { selected in
                            applySelection(selected: selected)
                        }
                    )
                }
            }
            .onChange(of: suggestion != nil) { _, isShown in
                // popover 떴을 때만 NSEvent local monitor 활성. TextEditor/TextField 가
                // 화살표 / Enter 를 흡수하기 전에 우리가 먼저 가로챔.
                if isShown {
                    installKeyMonitor()
                } else {
                    removeKeyMonitor()
                }
            }
            .onDisappear { removeKeyMonitor() }
    }

    // MARK: - NSEvent key monitor

    private func installKeyMonitor() {
        if keyMonitor.token != nil { return }
        keyMonitor.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let token = keyMonitor.token {
            NSEvent.removeMonitor(token)
            keyMonitor.token = nil
        }
    }

    /// 반환 true = 우리가 처리, event swallow.
    /// false = passthrough.
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let suggestion, !suggestion.candidates.isEmpty else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cleanMods = mods.subtracting([.numericPad, .function])
        switch event.keyCode {
        case 126:  // Up arrow
            guard cleanMods.isEmpty else { return false }
            let count = suggestion.candidates.count
            selectedIndex = (selectedIndex - 1 + count) % count
            return true
        case 125:  // Down arrow
            guard cleanMods.isEmpty else { return false }
            selectedIndex = (selectedIndex + 1) % suggestion.candidates.count
            return true
        case 36, 76:  // Return / Numpad Enter
            // Cmd+Enter (send) 는 우리가 안 잡음 → underlying TextEditor 의 Cmd+Enter
            // keyboardShortcut 으로 흐름.
            guard cleanMods.isEmpty,
                  selectedIndex < suggestion.candidates.count else {
                return false
            }
            applySelection(selected: suggestion.candidates[selectedIndex])
            return true
        case 53:  // Esc
            guard cleanMods.isEmpty else { return false }
            self.suggestion = nil
            return true
        default:
            return false
        }
    }

    /// NSEvent monitor token 을 @State 에 담기 위한 reference box.
    /// SwiftUI struct 의 immutable self 안에서도 token 을 mutate 가능.
    /// onDisappear 가 cleanup — deinit 은 Swift 6 nonisolated isolation 회피 위해 생략.
    @MainActor
    final class KeyMonitorBox {
        var token: Any?
        init() { self.token = nil }
    }

    private func applySelection(selected: DiscoveredSlashCommand) {
        guard let current = suggestion else { return }
        // must-fix /team HIGH-3 — replaceRange 가 현재 draft 의 indices 안에 있는지 guard.
        // suggestion 발급 후 사용자가 추가 타이핑/삭제하면 stale 가능.
        guard current.replaceRange.lowerBound <= draft.endIndex,
              current.replaceRange.upperBound <= draft.endIndex else {
            suggestion = nil
            return
        }
        let newDraft = engine.applySelection(
            draft: draft, suggestion: current, selected: selected
        )
        draft = newDraft
        lastAppliedDraft = newDraft  // .task latch 활성화
        suggestion = nil
    }
}
