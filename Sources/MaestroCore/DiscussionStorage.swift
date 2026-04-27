import Foundation

/// v0.5.4 — 토론 디스크 영속화 actor. `discussions/<id>.json` per-file.
///
/// 디자인:
/// - per-file: 한 파일이 corrupt 돼도 다른 토론 영향 없음 (AgentMemoStore 와 동일).
/// - atomic write: partial 저장 방지.
/// - 0o600 perms: 다른 로컬 사용자가 읽지 못하게.
/// - 손상 파일 silently skip (loadAll 시).
public actor DiscussionStorage {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func save(_ record: DiscussionRecord) throws {
        try ensureDirectory()
        let url = directory.appending(
            path: "\(record.id.rawValue).json", directoryHint: .notDirectory
        )
        let data = try JSONEncoder.maestro.encode(record)
        try data.write(to: url, options: [.atomic])
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    public func load(id: ThreadID) throws -> DiscussionRecord? {
        let url = directory.appending(
            path: "\(id.rawValue).json", directoryHint: .notDirectory
        )
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.maestro.decode(DiscussionRecord.self, from: data)
    }

    public func loadAll() throws -> [DiscussionRecord] {
        try ensureDirectory()
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var records: [DiscussionRecord] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let record = try? JSONDecoder.maestro.decode(
                DiscussionRecord.self, from: data
               ) {
                records.append(record)
            }
        }
        return records.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func delete(id: ThreadID) throws {
        let url = directory.appending(
            path: "\(id.rawValue).json", directoryHint: .notDirectory
        )
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: directory.path
            )
        }
    }
}
