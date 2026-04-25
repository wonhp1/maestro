import MaestroCore
import SwiftUI

/// 참여자 한 명을 표현하는 동그라미 아바타 — 이니셜 + 일관된 색상.
///
/// 색은 `agentId.rawValue` 의 hash 로 결정 — 같은 agent 는 항상 같은 색.
/// SF Symbol 대신 텍스트 이니셜로 표시 (Phase 19+ 에 actual 이미지 옵션 추가 가능).
struct ParticipantAvatar: View {
    let agentId: AgentID
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(palette[paletteIndex])
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityLabel(Text(agentId.rawValue))
    }

    private var initial: String {
        let raw = agentId.rawValue
        let trimmed = raw.replacingOccurrences(of: "agent-", with: "")
        return String(trimmed.prefix(1)).uppercased()
    }

    private var paletteIndex: Int {
        // 결정론적 hash — 같은 agent 는 항상 같은 색
        let hash = agentId.rawValue.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return abs(hash) % palette.count
    }

    private let palette: [Color] = [
        .blue, .purple, .pink, .orange, .green, .teal, .indigo, .red, .brown, .mint,
    ]
}

#Preview {
    HStack {
        ParticipantAvatar(agentId: AgentID(rawValue: "alice"))
        ParticipantAvatar(agentId: AgentID(rawValue: "bob"))
        ParticipantAvatar(agentId: AgentID(rawValue: "carol"))
        ParticipantAvatar(agentId: AgentID(rawValue: "dave"), size: 40)
    }
    .padding()
}
