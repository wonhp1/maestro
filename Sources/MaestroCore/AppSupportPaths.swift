import Foundation

/// 모든 사용자 데이터의 파일시스템 경로를 중앙에서 관리.
///
/// 기본 위치: `~/Library/Application Support/Maestro/`
///
/// ```
/// <root>/
/// ├── config.json
/// ├── folders.json
/// ├── sessions/<session-id>.json
/// ├── agents/<agent-id>.json
/// ├── inbox/<agent-id>/<envelope-id>.json
/// ├── outbox/<agent-id>/<envelope-id>.json
/// ├── threads/<thread-id>.jsonl
/// ├── failed/<envelope-id>.json       # DLQ (Phase 11)
/// └── logs/
/// ```
///
/// 테스트 코드는 `AppSupportPaths(root: tempDir)` 로 임의 루트 주입 가능.
public struct AppSupportPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// macOS Application Support 에 위치한 기본 경로.
    public static func forApplication(
        fileManager: FileManager = .default,
        appName: String = "Maestro"
    ) throws -> AppSupportPaths {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appRoot = support.appending(path: appName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: appRoot, withIntermediateDirectories: true)
        return AppSupportPaths(root: appRoot)
    }

    // MARK: Top-level files

    public var configFile: URL {
        root.appending(path: "config.json", directoryHint: .notDirectory)
    }

    public var foldersFile: URL {
        root.appending(path: "folders.json", directoryHint: .notDirectory)
    }

    public var preferencesFile: URL {
        root.appending(path: "preferences.json", directoryHint: .notDirectory)
    }

    // MARK: Directories

    public var sessionsDir: URL { root.appending(path: "sessions", directoryHint: .isDirectory) }
    public var agentsDir: URL { root.appending(path: "agents", directoryHint: .isDirectory) }
    public var inboxRoot: URL { root.appending(path: "inbox", directoryHint: .isDirectory) }
    public var outboxRoot: URL { root.appending(path: "outbox", directoryHint: .isDirectory) }
    public var threadsDir: URL { root.appending(path: "threads", directoryHint: .isDirectory) }
    public var failedDir: URL { root.appending(path: "failed", directoryHint: .isDirectory) }
    public var logsDir: URL { root.appending(path: "logs", directoryHint: .isDirectory) }
    public var crashesDir: URL { root.appending(path: "crashes", directoryHint: .isDirectory) }

    // MARK: Per-entity paths

    public func sessionFile(id: SessionID) -> URL {
        sessionsDir.appending(path: "\(id.rawValue).json", directoryHint: .notDirectory)
    }

    public func agentFile(id: AgentID) -> URL {
        agentsDir.appending(path: "\(id.rawValue).json", directoryHint: .notDirectory)
    }

    public func inboxDir(for agent: AgentID) -> URL {
        inboxRoot.appending(path: agent.rawValue, directoryHint: .isDirectory)
    }

    public func outboxDir(for agent: AgentID) -> URL {
        outboxRoot.appending(path: agent.rawValue, directoryHint: .isDirectory)
    }

    public func inboxFile(agent: AgentID, envelope: EnvelopeID) -> URL {
        inboxDir(for: agent)
            .appending(path: "\(envelope.rawValue).json", directoryHint: .notDirectory)
    }

    public func outboxFile(agent: AgentID, envelope: EnvelopeID) -> URL {
        outboxDir(for: agent)
            .appending(path: "\(envelope.rawValue).json", directoryHint: .notDirectory)
    }

    public func threadFile(id: ThreadID) -> URL {
        threadsDir.appending(path: "\(id.rawValue).jsonl", directoryHint: .notDirectory)
    }

    public func failedFile(envelope: EnvelopeID) -> URL {
        failedDir.appending(path: "\(envelope.rawValue).json", directoryHint: .notDirectory)
    }

    // MARK: Directory creation

    /// 모든 디렉토리를 (존재하지 않으면) 생성. 첫 실행 시 호출.
    ///
    /// 모든 디렉토리는 `0700` 권한 (소유자만 접근) 으로 설정 — 로컬 다중 사용자
    /// 환경에서 다른 사용자의 spy 방어.
    public func ensureAllDirectoriesExist(
        fileManager: FileManager = .default
    ) throws {
        let allDirs = [
            root, sessionsDir, agentsDir, inboxRoot, outboxRoot,
            threadsDir, failedDir, logsDir, crashesDir,
        ]
        for dir in allDirs {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: dir.path
            )
        }
    }
}
