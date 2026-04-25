import Foundation
import Observation

/// 커맨드 팔레트의 driving state — query / 결과 / 선택 / 최근 추적.
///
/// ## 동작
/// - `query` 변경 → `search()` 호출 → `results` 갱신
/// - 최근 commands 는 query 가 비어있을 때 상단에 prepend
/// - `Enter` (또는 클릭) → `execute(selectedIndex)` → handler 호출 + record
///
/// ## 동시성
/// `@MainActor` — SwiftUI 와 같은 isolation. registry actor 는 `await` 로 호출.
@MainActor
@Observable
public final class CommandPaletteViewModel {
    public var query: String = "" {
        didSet { scheduleSearch() }
    }
    public var isPresented: Bool = false
    public private(set) var results: [Command] = []
    public var selectedIndex: Int = 0

    private let registry: CommandRegistry
    private let recentTracker: RecentCommandTracker
    @ObservationIgnored
    private var searchTask: Task<Void, Never>?
    /// dismiss 도중 query reset 이 search 를 spawn 하지 않도록 가드 (must-fix HIGH-2).
    @ObservationIgnored
    private var suppressSearch: Bool = false

    /// debounce — 테스트 주입 가능 (must-fix MED-5).
    public let debounceNanos: UInt64

    public init(
        registry: CommandRegistry,
        recentTracker: RecentCommandTracker,
        debounceNanos: UInt64 = 80_000_000
    ) {
        self.registry = registry
        self.recentTracker = recentTracker
        self.debounceNanos = debounceNanos
    }

    /// 팔레트 열기 + 첫 검색. 이미 열려있으면 dismiss (Cmd+K toggle, must-fix MED-1).
    public func present() async {
        if isPresented {
            dismiss()
            return
        }
        isPresented = true
        suppressSearch = true
        query = ""
        suppressSearch = false
        await refresh()
    }

    public func dismiss() {
        isPresented = false
        searchTask?.cancel()
        searchTask = nil
        // query reset 이 didSet 통해 scheduleSearch 호출하지 않도록 가드 (HIGH-2)
        suppressSearch = true
        query = ""
        suppressSearch = false
        results = []
        selectedIndex = 0
    }

    /// 키보드 ↑/↓ — 선택 이동.
    public func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        selectedIndex = (selectedIndex + delta + count) % count
    }

    /// Enter — 현재 선택 실행.
    public func executeSelected() async {
        guard results.indices.contains(selectedIndex) else { return }
        let command = results[selectedIndex]
        recentTracker.record(commandID: command.id)
        dismiss()
        await command.handler()
    }

    public func execute(commandID: String) async {
        guard let command = results.first(where: { $0.id == commandID }) else { return }
        recentTracker.record(commandID: command.id)
        dismiss()
        await command.handler()
    }

    private func scheduleSearch() {
        guard !suppressSearch else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self, debounceNanos] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        let q = query
        let allResults = await registry.search(query: q)
        let final: [Command]
        if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // recent 항목은 .recent 카테고리로 retag — 시각 cue 일관 (must-fix MED-2)
            let recent = recentTracker.recentCommands(in: allResults).map { cmd in
                Command(
                    id: cmd.id,
                    title: cmd.title,
                    subtitle: cmd.subtitle,
                    category: .recent,
                    shortcutHint: cmd.shortcutHint,
                    handler: cmd.handler
                )
            }
            let recentIDs = Set(recent.map(\.id))
            let rest = allResults.filter { !recentIDs.contains($0.id) }
            final = recent + rest
        } else {
            final = allResults
        }
        self.results = final
        if !results.indices.contains(selectedIndex) {
            selectedIndex = 0
        }
    }
}
