import Foundation

/// 사용자 폴더 등록 + 영속화를 담당하는 actor.
///
/// ## 책임
/// - 폴더 추가/삭제/업데이트 (CRUD)
/// - `folders.json` 디스크 영속화 (FileStore 통한 atomic write + 0600 perms)
/// - 변경 이벤트 broadcast — UI (`FolderViewModel`) 가 구독하여 자동 새로고침
///
/// ## 동시성
/// actor 로 직렬화. 동시 add/remove 호출은 큐잉 — 디스크 일관성 보장.
///
/// ## 디스크 포맷
/// `FoldersFile.version` 으로 향후 마이그레이션 버전 관리. 현재 v1.
///
/// ## 보안
/// - 추가 시점에 `FolderRegistration.validateDisplayName/validatePath` 강제.
/// - id 중복 차단 — 같은 `FolderID` 두 번 추가 시 throws.
/// - 같은 `path` 두 번 추가 시 silently no-op 이 아닌 throws — 사용자가 의도를
///   인지하도록 (UX 요건).
public actor FolderRegistry {
    private let store: FileStore<FoldersFile>
    private var folders: [FolderRegistration] = []
    private var continuations: [UUID: AsyncStream<FolderRegistryEvent>.Continuation] = [:]
    private var loaded: Bool = false

    public init(paths: AppSupportPaths) {
        self.store = FileStore<FoldersFile>(path: paths.foldersFile)
    }

    /// 디스크에서 로드 (idempotent — 이미 로드됐으면 no-op).
    /// 파일 미존재 시 빈 목록으로 시작 (정상 — 첫 실행).
    ///
    /// **보안**: 디코드된 폴더는 해당 시점에 disk-trust 만 받음 — 그 후
    /// `validateDisplayName` + `validatePath` 를 다시 통과시킨다. 통과 못한 항목은
    /// `invalidEntries` 에 모이고 디스크에서 prune (재 persist). 누군가가
    /// `folders.json` 에 직접 path: `/etc` + bidi 이름을 주입한 시나리오 차단.
    public func loadFromDisk() async throws {
        guard !loaded else { return }
        if let file = try await store.loadIfExists() {
            var valid: [FolderRegistration] = []
            var pruned: [FolderRegistration] = []
            for entry in file.folders {
                do {
                    try FolderRegistration.validateDisplayName(entry.displayName)
                    let resolved = try FolderRegistration.validatePath(entry.path)
                    var sanitized = entry
                    sanitized.path = resolved
                    valid.append(sanitized)
                } catch {
                    pruned.append(entry)
                }
            }
            folders = valid
            if !pruned.isEmpty {
                // 손상된 항목 발견 — 디스크 cleanup.
                try await persist()
            }
            invalidEntries = pruned
        }
        loaded = true
    }

    /// 마지막 로드에서 prune 된 항목들 — UI 가 사용자에게 알림 가능.
    public private(set) var invalidEntries: [FolderRegistration] = []

    /// 현재 등록된 폴더 (등록 순서 = createdAt 순).
    public func list() -> [FolderRegistration] {
        folders.sorted { $0.createdAt < $1.createdAt }
    }

    public func get(id: FolderID) -> FolderRegistration? {
        folders.first { $0.id == id }
    }

    /// 새 폴더 등록. 디스플레이 이름 / 경로 검증 + 심볼릭 링크 해소 후 저장.
    ///
    /// `validatePath` 가 반환한 resolved URL 을 사용 — 사용자가 선택한 심볼릭 링크는
    /// 실제 디렉토리로 정규화되어 저장된다 (Phase 11 spawn 시 cwd 일관성 보장).
    /// 중복 경로 검사는 resolved 기준 — `~/code` 와 `~/code -> /Volumes/X` 가 같은
    /// 폴더로 인식됨.
    @discardableResult
    public func add(
        displayName: String,
        path: URL,
        adapterId: AdapterID,
        id: FolderID = .new()
    ) async throws -> FolderRegistration {
        try FolderRegistration.validateDisplayName(displayName)
        let resolvedPath = try FolderRegistration.validatePath(path)

        if folders.contains(where: { $0.id == id }) {
            throw FolderRegistryError.duplicateID(id: id)
        }
        if folders.contains(where: { $0.path == resolvedPath }) {
            throw FolderRegistryError.duplicatePath(path: resolvedPath)
        }
        let registration = FolderRegistration(
            id: id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            path: resolvedPath,
            adapterId: adapterId
        )
        folders.append(registration)
        try await persist()
        broadcast(.added(registration))
        return registration
    }

    /// 폴더 제거. 없으면 throws.
    public func remove(id: FolderID) async throws {
        guard let removed = folders.first(where: { $0.id == id }) else {
            throw FolderRegistryError.notFound(id: id)
        }
        folders.removeAll { $0.id == id }
        try await persist()
        broadcast(.removed(removed))
    }

    /// 디스플레이 이름 / 어댑터 / 모델 변경. 경로는 변경 불가 (재등록 권장).
    /// modelId 에 빈 문자열 또는 nil 을 넘기면 "기본 모델" 로 reset.
    @discardableResult
    public func update(
        id: FolderID,
        displayName: String? = nil,
        adapterId: AdapterID? = nil,
        modelId: String?? = nil
    ) async throws -> FolderRegistration {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            throw FolderRegistryError.notFound(id: id)
        }
        var folder = folders[index]
        if let newName = displayName {
            try FolderRegistration.validateDisplayName(newName)
            folder.displayName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let newAdapter = adapterId {
            folder.adapterId = newAdapter
        }
        if let newModel = modelId {
            // Optional<Optional<String>> — 외부 nil = "변경 안 함", inner nil = "기본 모델"
            let trimmed = newModel?.trimmingCharacters(in: .whitespacesAndNewlines)
            folder.modelId = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
        folders[index] = folder
        try await persist()
        broadcast(.updated(folder))
        return folder
    }

    /// I-NEW-2 fix — 폴더의 영속 sessionId 갱신. ChatSessionStore 가 세션을 처음
    /// 만들 때 호출하여 다음 launch 가 같은 ID 로 `claude --resume` 가능.
    public func setSessionId(id: FolderID, sessionId: SessionID) async throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            throw FolderRegistryError.notFound(id: id)
        }
        guard folders[index].sessionId != sessionId else { return }
        folders[index].sessionId = sessionId
        try await persist()
        broadcast(.updated(folders[index]))
    }

    /// 폴더 사용 시각 업데이트 (UI 에서 폴더 클릭 시 호출).
    public func touch(id: FolderID, now: Date = Date()) async throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            throw FolderRegistryError.notFound(id: id)
        }
        folders[index].lastUsedAt = now
        try await persist()
        broadcast(.updated(folders[index]))
    }

    /// 폴더 변경 이벤트 스트림. UI 가 한 번만 구독해서 reconcile.
    public func events() -> AsyncStream<FolderRegistryEvent> {
        AsyncStream { continuation in
            let token = UUID()
            continuations[token] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeContinuation(token: token) }
            }
        }
    }

    private func removeContinuation(token: UUID) {
        continuations[token] = nil
    }

    private func broadcast(_ event: FolderRegistryEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func persist() async throws {
        let file = FoldersFile(version: FoldersFile.currentVersion, folders: folders)
        try await store.save(file)
    }
}

/// 폴더 변경 이벤트.
public enum FolderRegistryEvent: Sendable, Equatable {
    case added(FolderRegistration)
    case removed(FolderRegistration)
    case updated(FolderRegistration)
}

/// 디스크 직렬화 wrapper. `version` 필드로 향후 마이그레이션 가능.
public struct FoldersFile: Codable, Hashable, Sendable {
    public static let currentVersion: Int = 1
    public let version: Int
    public let folders: [FolderRegistration]

    public init(version: Int, folders: [FolderRegistration]) {
        self.version = version
        self.folders = folders
    }
}

public enum FolderRegistryError: Error, Equatable, Sendable {
    case duplicateID(id: FolderID)
    case duplicatePath(path: URL)
    case notFound(id: FolderID)
}
