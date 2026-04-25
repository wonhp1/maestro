import SwiftUI

/// ●●● 점 세개가 순차적으로 부풀었다 줄어드는 typing indicator.
///
/// Reduce-motion 환경에서는 정적 "•••" 표시 (a11y 배려).
struct TypingIndicator: View {
    @State private var phase: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { idx in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(reduceMotion ? 1.0 : (phase == idx ? 1.4 : 1.0))
                    .opacity(reduceMotion ? 0.6 : (phase == idx ? 1.0 : 0.5))
            }
        }
        .accessibilityLabel("입력 중")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                phase = (phase + 1) % 3
            }
        }
    }
}
