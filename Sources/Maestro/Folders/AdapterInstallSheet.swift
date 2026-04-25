import MaestroCore
import SwiftUI

/// 미설치 어댑터 자동 설치 진행 시트.
///
/// VendorPickerSheet 또는 FolderSettingsSheet 의 "설치하기" 버튼이 트리거.
/// 진행 상태 (idle / running / success / failed) + 출력 로그 표시.
struct AdapterInstallSheet: View {
    let adapterId: String
    let displayName: String
    let onCompletion: (Bool) -> Void  // true = 설치 성공

    @State private var phase: Phase = .idle
    @State private var outputLog: String = ""

    enum Phase: Equatable {
        case idle
        case running
        case success(stdoutTail: String)
        case failed(message: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            phaseDetail
            footer
        }
        .padding(20)
        .frame(width: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(displayName) 설치")
                .font(.title3).bold()
            Text(specHint)
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var specHint: String {
        guard let spec = AdapterInstaller.spec(for: adapterId) else {
            return "이 어댑터는 자동 설치를 지원하지 않습니다."
        }
        return "`\(spec.packageManager) \(spec.installArguments.joined(separator: " "))` 를 실행합니다."
    }

    @ViewBuilder
    private var phaseDetail: some View {
        switch phase {
        case .idle:
            Text("아래 '설치 시작' 버튼을 눌러주세요.")
                .font(.callout).foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("설치 중… (수십 초 ~ 수 분)").font(.callout)
            }
        case .success(let tail):
            VStack(alignment: .leading, spacing: 6) {
                Label("설치 완료", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
                if !tail.isEmpty {
                    ScrollView { Text(tail).font(.system(.caption, design: .monospaced)) }
                        .frame(maxHeight: 120)
                        .padding(8).background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("설치 실패", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red).font(.headline)
                ScrollView { Text(message).font(.system(.caption, design: .monospaced)) }
                    .frame(maxHeight: 160)
                    .padding(8).background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            switch phase {
            case .idle:
                Button("취소", role: .cancel) { onCompletion(false) }
                    .keyboardShortcut(.cancelAction)
                Button("설치 시작") { Task { await runInstall() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .running:
                Button("취소", role: .cancel) { onCompletion(false) }
                    .disabled(true)
            case .success:
                Button("닫기") { onCompletion(true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("닫기") { onCompletion(false) }
                    .keyboardShortcut(.cancelAction)
                Button("재시도") { Task { await runInstall() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func runInstall() async {
        phase = .running
        let installer = AdapterInstaller()
        do {
            let result = try await installer.install(adapterId: adapterId)
            switch result {
            case .success(let tail):
                phase = .success(stdoutTail: tail)
            case .failed(let exitCode, let stderr):
                phase = .failed(message: "exit \(exitCode):\n\(stderr)")
            }
        } catch let AdapterInstallerError.packageManagerMissing(name) {
            phase = .failed(message: noPackageManagerMessage(name: name))
        } catch let AdapterInstallerError.unsupportedAdapter(id) {
            phase = .failed(message: "어댑터 '\(id)' 는 자동 설치 미지원입니다.")
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    private func noPackageManagerMessage(name: String) -> String {
        switch name {
        case "npm":
            return """
            npm 을 찾지 못했어요. Node.js 가 설치되어 있어야 합니다.
            https://nodejs.org 에서 LTS 버전을 받아 설치한 후 다시 시도해주세요.
            """
        case "pip", "pip3":
            return """
            pip3 을 찾지 못했어요. Python 3 가 설치되어 있어야 합니다.
            macOS 기본 Python 또는 https://www.python.org 에서 받아 설치해주세요.
            """
        default:
            return "패키지 매니저 '\(name)' 를 찾지 못했어요."
        }
    }
}
