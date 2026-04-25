import MaestroCore
import SwiftUI

/// 첫 실행 사용자에게 보여주는 3단계 온보딩 sheet.
///
/// `MaestroApp` 의 메인 윈도우가 `preferences.firstRunCompleted == false` 일 때 sheet
/// 로 띄움. 사용자가 "건너뛰기" 또는 마지막 단계에서 "시작" → 완료.
struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onAddFolder: @MainActor () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            header

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .padding(32)
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            stepDots
            Spacer()
            Button("건너뛰기") { viewModel.skip() }
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= viewModel.currentStep.rawValue
                          ? Color.accentColor
                          : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.currentStep.title)
                .font(.title2)
                .bold()

            switch viewModel.currentStep {
            case .welcome:
                Text("Maestro 는 여러 AI 코딩 에이전트(Claude, Aider 등)를 한 화면에서 오케스트레이션 하는 macOS 앱입니다.\n\n폴더 단위로 에이전트를 묶고 메시지를 주고받으며, 토론을 운영할 수 있습니다.")
                    .foregroundStyle(.secondary)
            case .detectAgents:
                if viewModel.detectedAdapters.isEmpty {
                    Text("설치된 에이전트를 자동 감지합니다. 환경설정에서 활성화 여부를 변경할 수 있습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("감지됨").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(viewModel.detectedAdapters, id: \.self) { id in
                            Label(id, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            case .firstFolder:
                VStack(alignment: .leading, spacing: 12) {
                    Text("작업할 폴더를 한 개 추가해 보세요. 나중에 사이드바에서 더 추가할 수 있습니다.")
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            await onAddFolder()
                            viewModel.hasAddedFirstFolder = true
                        }
                    } label: {
                        Label("폴더 추가…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    if viewModel.hasAddedFirstFolder {
                        Label("폴더 추가됨", systemImage: "checkmark")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if viewModel.currentStep != .welcome {
                Button("이전") { viewModel.goBack() }
            }
            Spacer()
            Button(viewModel.currentStep == .firstFolder ? "시작" : "다음") {
                viewModel.advance()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }
}
