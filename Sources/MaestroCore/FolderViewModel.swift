import Foundation
import Observation

/// 사이드바를 driving 하는 ViewModel — 등록된 폴더 목록 + 선택 상태 + 추가/삭제 액션.
///
/// ## 책임
/// - 부팅 시 `FolderRegistry.loadFromDisk()` 호출
/// - 변경 이벤트 (added/removed/updated) 구독 → snapshot 갱신 → SwiftUI 자동 렌더
/// - "+ 폴더 추가" 진입점 — `FolderPicking` 호출 후 registry 에 등록
/// - 사용자 액션 (선택 / 삭제) 시 errorMessage 로 결과 전달
///
/// ## 동시성
/// `@MainActor` — UI 와 같은 isolation. registry actor 는 await 로 호출.
///
/// ## 에러 처리
/// 모든 사용자 가시 작업은 `errorMessage` 로 비동기 알림 (throws 하지 않음).
/// SwiftUI alert 가 `.alert(isPresented:)` 로 구독.
@MainActor
@Observable
public final class FolderViewModel {
    public private(set) var folders: [FolderRegistration] = []
    public var selectedFolderID: FolderID?
    public private(set) var isLoading: Bool = false
    public var errorMessage: String?

    /// `addFolderViaPicker` 가 polder picker 결과를 받은 직후, vendor 선택을 사용자에게
    /// 받기 위한 중간 상태. UI 가 이 값을 관찰해서 vendor sheet 를 띄움.
    /// `confirmPendingAdd` 또는 `cancelPendingAdd` 로 nil 로 돌아감.
    public var pendingFolderURL: URL?

    private let registry: FolderRegistry
    private let picker: FolderPicking
    private let defaultAdapterID: AdapterID
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    public init(
        registry: FolderRegistry,
        picker: FolderPicking,
        defaultAdapterID: AdapterID
    ) {
        self.registry = registry
        self.picker = picker
        self.defaultAdapterID = defaultAdapterID
    }

    deinit {
        observationTask?.cancel()
    }

    /// 첫 진입 시 호출 — 디스크 로드 + 변경 스트림 구독 시작.
    public func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await registry.loadFromDisk()
            folders = await registry.list()
        } catch {
            errorMessage = "폴더 목록 로드 실패: \(error.localizedDescription)"
        }
        startObserving()
    }

    private func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self, registry] in
            let stream = await registry.events()
            for await _ in stream {
                guard let self else { return }
                let updated = await registry.list()
                await MainActor.run {
                    self.folders = updated
                }
            }
        }
    }

    /// "+ 폴더 추가" 액션 — picker 호출 후 vendor 선택을 위해 `pendingFolderURL` set.
    /// 실제 등록은 사용자가 vendor 를 고른 뒤 `confirmPendingAdd(adapterId:)` 호출.
    public func addFolderViaPicker() async {
        do {
            guard let url = try await picker.presentPicker(suggested: nil) else {
                return  // 사용자 취소 — 정상.
            }
            pendingFolderURL = url
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    /// vendor sheet 에서 사용자가 어댑터 선택 → 실제 registry 등록.
    public func confirmPendingAdd(adapterId: AdapterID) async {
        guard let url = pendingFolderURL else { return }
        do {
            let displayName = url.lastPathComponent
            let registered = try await registry.add(
                displayName: displayName,
                path: url,
                adapterId: adapterId
            )
            await refreshFolders()
            selectedFolderID = registered.id
            pendingFolderURL = nil
        } catch {
            errorMessage = humanReadable(error)
            pendingFolderURL = nil
        }
    }

    /// 사용자가 vendor sheet 를 취소 — pending 상태 클리어.
    public func cancelPendingAdd() {
        pendingFolderURL = nil
    }

    /// 폴더 삭제. UI 에서 이미 confirm 다이얼로그를 거친 후 호출 가정.
    public func deleteFolder(id: FolderID) async {
        let wasSelected = (selectedFolderID == id)
        do {
            try await registry.remove(id: id)
            await refreshFolders()
            if wasSelected {
                selectedFolderID = folders.first?.id
            }
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    /// 폴더 표시 이름 변경.
    public func rename(id: FolderID, to newName: String) async {
        do {
            try await registry.update(id: id, displayName: newName)
            await refreshFolders()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    /// 폴더의 어댑터 변경 (설정 시트).
    public func changeAdapter(id: FolderID, to adapterId: AdapterID) async {
        do {
            try await registry.update(id: id, adapterId: adapterId)
            await refreshFolders()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    /// 사용자가 사이드바에서 폴더 클릭 — lastUsedAt 기록 + 선택.
    public func select(id: FolderID) async {
        selectedFolderID = id
        do {
            try await registry.touch(id: id)
            await refreshFolders()
        } catch {
            // touch 실패는 사용자 가시 에러 아님 — 로그만.
            errorMessage = nil
        }
    }

    /// 디스크/registry 와 UI 스냅샷 동기화. 액션 직후 일관성 보장 — events 스트림은
    /// 외부 (다른 인스턴스) 변경을 위한 backup channel.
    private func refreshFolders() async {
        folders = await registry.list()
    }

    public func dismissError() {
        errorMessage = nil
    }

    private func humanReadable(_ error: Error) -> String {
        switch error {
        case FolderRegistrationError.emptyDisplayName:
            return "폴더 이름이 비어 있습니다."
        case FolderRegistrationError.displayNameTooLong(let length):
            return "폴더 이름이 너무 깁니다 (\(length)자, 최대 128자)."
        case FolderRegistrationError.displayNameContainsControlCharacter:
            return "폴더 이름에 제어 문자가 포함되어 있습니다."
        case FolderRegistrationError.pathMustBeFileURL:
            return "선택된 경로가 파일 URL 이 아닙니다."
        case FolderRegistrationError.pathMustBeAbsolute:
            return "선택된 경로가 절대 경로가 아닙니다."
        case FolderRegistrationError.pathIsNotADirectory(let path):
            return "선택된 경로가 디렉토리가 아닙니다: \(path)"
        case FolderRegistryError.duplicatePath(let path):
            return "이미 등록된 폴더입니다: \(path.path)"
        case FolderRegistryError.duplicateID:
            return "내부 오류: 폴더 ID 충돌."
        case FolderRegistryError.notFound:
            return "폴더를 찾을 수 없습니다."
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Display name resolver (v0.4.8)

public extension FolderViewModel {
    /// AgentID → 사용자 친화 displayName.
    ///
    /// - "control" literal → control 폴더의 displayName ("Control" 등)
    /// - "agent-{folder-uuid}" 합성 ID → 매칭 폴더의 displayName
    /// - 매칭 폴더가 없으면 raw rawValue 폴백 (폴더 삭제 후 영속 envelope 등)
    ///
    /// `folders` 배열을 매번 lookup 하므로 새 폴더 추가/이름 변경/삭제 시 자동 반영.
    /// linear scan 이지만 폴더 수가 보통 한 자릿수라 비용 무시 가능.
    func displayName(for agentID: AgentID) -> String {
        if agentID.rawValue == "control" {
            return folders.first(where: {
                ControlAgentProvisioner.isControlFolder($0.id)
            })?.displayName ?? "Control"
        }
        return folders.first { folder in
            "agent-\(folder.id.rawValue.lowercased())" == agentID.rawValue
        }?.displayName ?? agentID.rawValue
    }
}
