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
    /// v0.7.0 Phase 3 polish — recompute 의 in-flight Task. typing 마다 cancel-restart.
    @State private var currentTask: Task<Void, Never>?

    /// pure logic — view rebuild 마다 새로 만들어도 비용 없음 (struct, no state).
    private let engine = SlashSuggestionEngine()

    func body(content: Content) -> some View {
        content
            .onAppear { recompute(for: draft) }
            .onChange(of: draft) { _, newValue in
                recompute(for: newValue)
            }
            .popover(
                isPresented: Binding(
                    get: { suggestion != nil },
                    set: { isShown in
                        if !isShown { suggestion = nil }
                    }
                ),
                // 입력창의 top-leading 에 anchor + arrowEdge: .bottom →
                // popover 가 입력창 위쪽으로 펼쳐짐. 입력창 글자 안 가림.
                attachmentAnchor: .point(.topLeading),
                arrowEdge: .bottom
            ) {
                if let suggestion {
                    SlashPopoverContent(
                        candidates: suggestion.candidates,
                        selectedIndex: selectedIndex,
                        onSelect: { selected in
                            applySelection(selected: selected)
                        }
                    )
                    // SwiftUI popover content 는 isPresented==true 동안 stable identity
                    // 라 candidates 변경 시 redraw 안 됨. query 를 id 로 → SwiftUI 가
                    // 매번 새 view 로 인식 → 강제 redraw.
                    .id(suggestion.query)
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

    /// 매 keystroke 마다 호출 — 새 Task 를 spawn 하고 in-flight task 를 cancel.
    /// `.task(id:)` + Task.sleep 의 cancel-restart race 를 피하기 위해 직접 manage.
    private func recompute(for newDraft: String) {
        // applySelection 직후 같은 draft → skip (re-trigger 차단).
        if newDraft == lastAppliedDraft { return }
        // 이전 in-flight task cancel.
        currentTask?.cancel()
        currentTask = Task { @MainActor in
            // typing burst 흡수 — 짧은 debounce. cancelled 면 즉시 종료.
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { return }
            let captured = newDraft
            // refresh — capture 후 fresh list. file source scan 비용은 registry 가 흡수.
            let snap = await registry.refresh()
            if Task.isCancelled { return }
            // 가장 최신 task 만 적용 — captured 와 현재 draft 불일치면 stale.
            if captured != draft { return }
            snapshot = snap
            suggestion = engine.evaluate(draft: captured, registrySnapshot: snap)
            selectedIndex = 0
        }
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
