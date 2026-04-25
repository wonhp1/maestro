import MaestroCore

/// 등록된 폴더 각각에 대한 "전환" 커맨드를 제공.
///
/// `⌘1` ~ `⌘9` 단축키 hint 를 첫 9개에 부여 (실제 단축키는 ControlTowerView 가 별도 등록).
struct FolderCommandProvider: CommandProvider {
    let folderViewModel: FolderViewModel

    func commands() async -> [Command] {
        let folders = await MainActor.run { folderViewModel.folders }
        return folders.enumerated().map { idx, folder in
            let id = "folder.switch.\(folder.id.rawValue)"
            let shortcutHint = idx < 9 ? "⌘\(idx + 1)" : nil
            return Command(
                id: id,
                title: "폴더 전환: \(folder.displayName)",
                subtitle: folder.path.path,
                category: .folder,
                shortcutHint: shortcutHint,
                handler: { [folderViewModel, folderID = folder.id] in
                    await folderViewModel.select(id: folderID)
                }
            )
        }
    }
}
