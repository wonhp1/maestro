import AppKit
import Foundation
import MaestroCore

/// `FolderPicking` 의 실제 구현 — NSOpenPanel 을 띄워 사용자가 폴더를 선택하게 함.
///
/// ## 동작
/// - `canChooseDirectories = true`, `canChooseFiles = false`, `canCreateDirectories = true`.
/// - 단일 선택. 다중 폴더 등록은 사용자가 반복 호출.
/// - 사용자 취소 시 nil. NSOpenPanel 자체는 throws 하지 않음.
///
/// ## 동시성
/// `presentPicker` 는 `@MainActor` 에서만 호출 — NSOpenPanel.runModal 이 main thread 강제.
/// `MainActor.run` 으로 dispatch 하지 않고 actor isolation 으로 강제.
public actor NSOpenPanelFolderPicker: FolderPicking {
    public init() {}

    public func presentPicker(suggested: URL?) async throws -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = String(localized: "folder.picker.prompt",
                                  defaultValue: "폴더 선택")
            panel.message = String(localized: "folder.picker.message",
                                   defaultValue: "Maestro 에서 작업할 폴더를 선택하세요.")
            if let suggested {
                panel.directoryURL = suggested
            }
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return nil }
            return url.standardizedFileURL
        }
    }
}
