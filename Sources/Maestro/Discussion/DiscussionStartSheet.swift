import MaestroCore
import SwiftUI

/// "+ 새 토론" 버튼이 트리거하는 모달 시트.
///
/// 사용자 입력:
/// - 주제 (TextField, 필수)
/// - 참가자 multi-select (체크박스 list, 최소 2명)
/// - moderator 전략 (segmented: 라운드 로빈 / 랜덤 / LLM)
/// - 최대 턴 수 (Slider 4-100, 기본 20)
///
/// 시작 → DiscussionStartViewModel.start() → 새 ThreadID 반환 → 시트 닫기.
struct DiscussionStartSheet: View {
    @Bindable var viewModel: DiscussionStartViewModel
    let dismiss: (ThreadID?) -> Void  // nil 이면 사용자 취소

    @State private var isStarting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Form {
                topicField
                participantsField
                moderatorField
                maxTurnsField
            }
            .formStyle(.grouped)

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            footer
        }
        .padding(20)
        .frame(width: 580)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("새 토론 시작")
                .font(.title2).bold()
            Text("여러 에이전트가 한 주제로 의견을 교환합니다. control 폴더가 결과를 종합해요.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var topicField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("주제")
            TextField("예: 새 기능 우선순위 정하기", text: $viewModel.topic)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var participantsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("참가자")
                Spacer()
                Text("\(viewModel.selectedParticipants.count) 선택")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if viewModel.availableParticipants.isEmpty {
                Text("등록된 폴더(에이전트) 가 2개 이상 필요해요. 사이드바에서 폴더를 추가하세요.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.availableParticipants) { option in
                        ParticipantToggle(option: option, viewModel: viewModel)
                    }
                }
            }
            Text("최소 2명 선택")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var moderatorField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("발언 순서")
            Picker("", selection: moderatorSelectionBinding) {
                Text("라운드 로빈").tag(ModeratorTag.roundRobin)
                Text("랜덤").tag(ModeratorTag.random)
                // LLM moderator 는 다음 릴리스에 활성화 — 지금 노출하면 silent fallback 위험.
            }
            .pickerStyle(.segmented)
            Text(moderatorHint)
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var maxTurnsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            maxTurnsHeader
            maxTurnsSlider
            Text("이 횟수에 도달하면 자동 종료. 5–20이 보통.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var maxTurnsHeader: some View {
        HStack {
            Text("최대 턴 수")
            Spacer()
            Text("\(viewModel.clampedMaxTurns)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var maxTurnsSlider: some View {
        let lower = Double(DiscussionStartViewModel.minMaxTurns)
        let upper = Double(DiscussionStartViewModel.maxMaxTurns)
        let binding = Binding<Double>(
            get: { Double(viewModel.maxTurns) },
            set: { viewModel.maxTurns = Int($0) }
        )
        return Slider(value: binding, in: lower...upper, step: 1)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout)
        }
        .padding(8)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("취소", role: .cancel) { dismiss(nil) }
                .keyboardShortcut(.cancelAction)
            Button(isStarting ? "시작 중…" : "시작") {
                Task { await handleStart() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canStart || isStarting)
        }
    }

    private func handleStart() async {
        isStarting = true
        defer { isStarting = false }
        do {
            let threadId = try await viewModel.start()
            dismiss(threadId)
        } catch {
            // errorMessage 는 이미 viewModel 가 set
        }
    }

    private enum ModeratorTag: String, Hashable { case roundRobin, random }

    private var moderatorSelectionBinding: Binding<ModeratorTag> {
        Binding(
            get: {
                switch viewModel.moderatorChoice {
                case .roundRobin: return .roundRobin
                case .random: return .random
                case .llm: return .roundRobin  // 노출되지 않는 케이스 — 안전 기본값
                }
            },
            set: { newValue in
                switch newValue {
                case .roundRobin: viewModel.moderatorChoice = .roundRobin
                case .random: viewModel.moderatorChoice = .random
                }
            }
        )
    }

    private var moderatorHint: String {
        switch viewModel.moderatorChoice {
        case .roundRobin: return "참가자 순서대로 순환."
        case .random: return "매 턴 무작위 선정 (같은 사람 두 번 가능)."
        case .llm: return ""
        }
    }
}

private struct ParticipantToggle: View {
    let option: DiscussionParticipantOption
    @Bindable var viewModel: DiscussionStartViewModel

    var body: some View {
        Toggle(isOn: bindingForOption) {
            HStack(spacing: 8) {
                ParticipantAvatar(agentId: option.agentId, size: 18)
                Text(option.displayName)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var bindingForOption: Binding<Bool> {
        Binding(
            get: { viewModel.selectedParticipants.contains(option.agentId) },
            set: { isOn in
                if isOn {
                    viewModel.selectedParticipants.insert(option.agentId)
                } else {
                    viewModel.selectedParticipants.remove(option.agentId)
                }
            }
        )
    }
}
