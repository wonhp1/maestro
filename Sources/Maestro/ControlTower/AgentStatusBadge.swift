import MaestroCore
import SwiftUI

/// 폴더 행 옆에 보이는 작은 status 인디케이터.
///
/// SwiftUI Color 매핑은 여기서만 수행 (Core 의 `AgentStatusColor` → `Color`).
struct AgentStatusBadge: View {
    let status: AgentStatus
    var compact: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color(for: status.symbolColor))
                .frame(width: 8, height: 8)
            if !compact {
                Text(status.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())  // .help() 가 hit 영역을 가지도록.
        .help(status.localizedDescription)
        .accessibilityLabel(Text(status.localizedDescription))
    }

    private func color(for token: AgentStatusColor) -> Color {
        switch token {
        case .gray: return .gray
        case .yellow: return .yellow
        case .green: return .green
        case .red: return .red
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        AgentStatusBadge(status: .offline, compact: false)
        AgentStatusBadge(status: .idle(lastActivityAt: Date()), compact: false)
        AgentStatusBadge(status: .active(operation: "프롬프트 처리 중"), compact: false)
        AgentStatusBadge(status: .error(message: "API 키 없음", occurredAt: Date()), compact: false)
    }
    .padding()
}
