import Foundation

/// Control 메타 에이전트 자동 프로비저닝.
///
/// ## 책임
/// - 부팅 시 1회 호출 — `~/Library/Application Support/Maestro/control-cwd/` 디렉토리
///   존재 보장
/// - `FolderRegistry` 에 control 폴더 자동 등록 (이미 있으면 skip)
/// - control 폴더는 fixed UUID — 재시작 후에도 동일 식별자
///
/// ## 식별자 규약
/// - FolderID: `00000000-0000-0000-0000-000000636c74` (마지막 8자 hex "control")
/// - displayName: "Control"
/// - adapterId: "claude" (control 은 항상 Claude — 메타 reasoning 필요)
public enum ControlAgentProvisioner {
    public static let controlFolderID: FolderID = {
        // hex "control" → 6c 74 — 16자리 hex 로 패딩 (00000000-0000-0000-0000-000000636c74)
        let raw = "00000000-0000-0000-0000-000000636c74"
        return (try? FolderID.validated(rawValue: raw)) ?? FolderID(rawValue: raw)
    }()

    public static let displayName = "Control"

    /// 부팅 시 호출 — 디렉토리 + 폴더 등록 모두 ensure.
    public static func provision(
        registry: FolderRegistry,
        appSupportRoot: URL,
        fileManager: FileManager = .default
    ) async throws -> FolderRegistration {
        // 1. cwd 디렉토리 ensure
        let cwd = appSupportRoot.appending(
            path: "control-cwd", directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: cwd, withIntermediateDirectories: true)

        // README 한번 작성 — control agent 가 자기 cwd 의 컨텍스트로 사용
        let readme = cwd.appending(path: "README.md", directoryHint: .notDirectory)
        if !fileManager.fileExists(atPath: readme.path) {
            let content = """
            # Maestro Control Agent

            This is the Maestro orchestrator agent's working directory.

            Do not store project files here. The agent uses this folder only as
            a Claude session anchor — actual coding/analysis is delegated to
            registered project agents via `RELAY_TO` tags.
            """
            try content.data(using: .utf8)?.write(to: readme)
        }

        // 2. registry 에 폴더 등록 (이미 있으면 그대로 반환)
        if let existing = await registry.get(id: controlFolderID) {
            return existing
        }

        let registration = try await registry.add(
            displayName: displayName,
            path: cwd,
            adapterId: AdapterID(rawValue: "claude"),
            id: controlFolderID
        )
        return registration
    }

    public static func isControlFolder(_ id: FolderID) -> Bool {
        id == controlFolderID
    }
}
