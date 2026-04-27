import MaestroCore
import SwiftUI

/// v0.7.0 Phase 2 — 입력창에 `/` 타이핑 시 뜨는 popover 의 컨텐츠 view.
///
/// SlashSuggestionsModifier 가 attach. 화살표/Enter/Esc 처리는 modifier 책임 —
/// 이 view 는 그저 후보 리스트 + 선택 highlight 만 표시.
struct SlashPopoverContent: View {
    let candidates: [DiscoveredSlashCommand]
    let selectedIndex: Int
    let onSelect: (DiscoveredSlashCommand) -> Void

    var body: some View {
        // ScrollView + LazyVStack — 100+ 후보 시 popover 가 화면 넘는 것 방지.
        // ScrollViewReader 로 selectedIndex 변경 시 visible 영역 안에 유지
        // (사용자 보고: 화살표 이동 시 scroll 안 따라옴).
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, item in
                        row(item: item, isSelected: index == selectedIndex)
                            .id(index)
                            .onTapGesture { onSelect(item) }
                        if index < candidates.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: 360)
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func row(item: DiscoveredSlashCommand, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text("/\(item.command.name)")
                .font(.body.monospaced())
                .foregroundStyle(isSelected ? .white : .primary)
            // 인수 힌트 — 회색 보조 텍스트 (Phase 3 polish 의 시발점).
            if let firstArg = item.command.arguments?.first {
                Text(firstArg)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .opacity(isSelected ? 0.85 : 0.85)
            }
            Spacer()
            // 출처 라벨 (회색). isSelected 시 투명도만 조정 — AnyShapeStyle 회피.
            Text(item.source.displayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(isSelected ? 0.85 : 0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
    }
}
