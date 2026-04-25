import Foundation

/// Thread-safe snapshot of registered folders — control agent's system prompt provider
/// reads it from a non-MainActor context, so we can't directly read `FolderViewModel.folders`
/// (which is `@MainActor`). `ControlTowerEnvironment` updates the snapshot on every folder
/// change, and the control adapter's closure reads it.
public final class FolderListSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var folders: [FolderRegistration] = []

    public init() {}

    public func update(_ folders: [FolderRegistration]) {
        lock.lock()
        defer { lock.unlock() }
        self.folders = folders
    }

    public func read() -> [FolderRegistration] {
        lock.lock()
        defer { lock.unlock() }
        return folders
    }
}
