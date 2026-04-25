import AppKit
import MaestroCore

/// 진단 번들 export 의 사용자 인터랙티브 wrapper — NSSavePanel + DiagnosticsBundle.create.
///
/// Settings → Advanced 또는 메뉴 → 진단 번들 내보내기 가 호출.
@MainActor
enum DiagnosticsExporter {
    static func exportInteractive(paths: AppSupportPaths) async {
        let panel = NSSavePanel()
        panel.title = "진단 번들 저장 위치"
        panel.message = "Maestro 진단 정보를 ZIP 으로 내보냅니다 (로그 / 설정 / 폴더 메타)."
        panel.nameFieldStringValue = defaultFilename()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bundle = DiagnosticsBundle()
        let sources: [URL] = [
            paths.preferencesFile,
            paths.foldersFile,
            paths.sessionsDir,
            paths.threadsDir,
            paths.logsDir,
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        do {
            _ = try await bundle.create(outputZipURL: url, sourcePaths: sources)
            await MainActor.run { showSuccessAlert(at: url) }
        } catch {
            await MainActor.run { showFailureAlert(error: error) }
        }
    }

    private static func defaultFilename() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: "-", with: "")
        return "Maestro-Diagnostics-\(timestamp).zip"
    }

    private static func showSuccessAlert(at url: URL) {
        let alert = NSAlert()
        alert.messageText = "진단 번들 저장 완료"
        alert.informativeText = url.path
        alert.alertStyle = .informational
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "Finder 에서 보기")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private static func showFailureAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "진단 번들 생성 실패"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}
