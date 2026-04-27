import MaestroCore
import SwiftUI

/// v0.5.0 — 토론이 종료된 상태일 때 DiscussionDetailView 하단에 노출되는 결론 +
/// 공유 패널. file_length 회피용으로 분리.
struct DiscussionConclusionView: View {
    @Bindable var viewModel: DiscussionViewModel
    var summarizer: DiscussionConclusionSummarizer?
    var sharer: DiscussionConclusionSharing?
    var agentDisplayResolver: (AgentID) -> String

    @Binding var conclusionDraft: String
    @Binding var shareTargets: Set<AgentID>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            conclusionHeader
            editor
            shareBlock
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.04))
    }

    private var conclusionHeader: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.tint)
            Text("결론").font(.headline)
            Spacer()
            if viewModel.isSummarizing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("요약 중…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                guard let summarizer else { return }
                Task { await viewModel.summarizeConclusion(using: summarizer) }
            } label: {
                Label(
                    viewModel.discussion.conclusion == nil ? "요약" : "다시 요약",
                    systemImage: "sparkles"
                )
            }
            .disabled(summarizer == nil || viewModel.isSummarizing)
            .help(summarizer == nil
                  ? "요약기를 사용할 수 없어요"
                  : "사회자 (control) 가 토론 본문을 한 단락으로 요약")
        }
    }

    private var editor: some View {
        TextEditor(text: $conclusionDraft)
            .font(.body)
            .frame(minHeight: 80, maxHeight: 200)
            .padding(6)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                if conclusionDraft.isEmpty && !viewModel.isSummarizing {
                    Text("아직 결론이 없어요. 위 \"요약\" 또는 직접 입력하세요.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 14)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: conclusionDraft) { _, new in
                let current = viewModel.discussion.conclusion ?? ""
                if new != current {
                    Task { await viewModel.updateConclusion(new) }
                }
            }
    }

    @ViewBuilder
    private var shareBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "paperplane.fill").foregroundStyle(.tint)
                Text("공유 대상").font(.subheadline.weight(.semibold))
                Spacer()
                if let sharedAt = viewModel.discussion.sharedAt {
                    Text("공유됨 · ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        + Text(sharedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            DiscussionShareChips(
                participants: viewModel.discussion.participants,
                selected: $shareTargets,
                labelFor: agentDisplayResolver
            )
            HStack(spacing: 8) {
                if viewModel.isSharing {
                    ProgressView().controlSize(.small)
                    Text("공유 중…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard let sharer else { return }
                    let targets = Array(shareTargets)
                    Task { await viewModel.shareConclusion(with: targets, using: sharer) }
                } label: {
                    Label("공유", systemImage: "paperplane")
                }
                .buttonStyle(.borderedProminent)
                .disabled(canShare == false)
                .help(shareHelp)
            }
        }
    }

    private var canShare: Bool {
        guard sharer != nil else { return false }
        guard !viewModel.isSharing else { return false }
        let trimmed = conclusionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !shareTargets.isEmpty
    }

    private var shareHelp: String {
        if sharer == nil { return "공유기를 사용할 수 없어요" }
        if conclusionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "결론을 먼저 작성하세요"
        }
        if shareTargets.isEmpty { return "공유 대상을 한 명 이상 선택하세요" }
        return "선택한 자식 메인 세션에 결론 메시지 전송"
    }
}

/// 공유 대상 chip 리스트 — 클릭 토글로 set 멤버십 변경.
struct DiscussionShareChips: View {
    let participants: [AgentID]
    @Binding var selected: Set<AgentID>
    let labelFor: (AgentID) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(participants, id: \.self) { agent in
                    let isOn = selected.contains(agent)
                    Button {
                        if isOn { selected.remove(agent) } else { selected.insert(agent) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                            Text(labelFor(agent))
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            isOn
                            ? Color.accentColor.opacity(0.18)
                            : Color.secondary.opacity(0.10)
                        )
                        .foregroundStyle(isOn ? Color.accentColor : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(labelFor(agent)) \(isOn ? "선택됨" : "선택 안 됨")")
                }
            }
        }
    }
}
