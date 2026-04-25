import Foundation
import Observation

/// `PreferencesSnapshot` 을 디스크에 영속화 + UI 가 읽고 쓰는 `@Observable` 모델.
///
/// ## 동작
/// - `bootstrap()` — 디스크 파일 로드 (없으면 default). 1회만 의미.
/// - 모든 setter 가 `scheduleAutosave()` 호출 — 100ms 디바운스 후 저장.
/// - 직접 `flush()` 호출로 강제 저장 가능 (테스트 / 종료 hook).
///
/// ## 동시성
/// `@MainActor @Observable` — UI 와 같은 isolation. 디스크 I/O 는 actor 내부 helper
/// (`FileStore`) 가 직렬화 + 백그라운드 hop.
///
/// ## 보안
/// `FileStore` 가 0600 권한 적용. 시크릿(API 키 등)은 절대 여기 저장 X — Keychain
/// 전용 (`APIKeyStorage`).
@MainActor
@Observable
public final class PreferencesStore {
    public private(set) var snapshot: PreferencesSnapshot

    @ObservationIgnored
    private let store: FileStore<PreferencesSnapshot>
    @ObservationIgnored
    private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored
    public let autosaveDebounceNanos: UInt64

    public init(
        path: URL,
        initial: PreferencesSnapshot = .default,
        autosaveDebounceNanos: UInt64 = 100_000_000
    ) {
        self.store = FileStore<PreferencesSnapshot>(path: path)
        self.snapshot = initial
        self.autosaveDebounceNanos = autosaveDebounceNanos
    }

    public func bootstrap() async {
        do {
            if let loaded = try await store.loadIfExists() {
                self.snapshot = loaded
            }
        } catch {
            // corrupt / unreadable — silent fallback to default. Phase 22 에서 telemetry.
        }
    }

    // MARK: - Mutation API

    public func setFirstRunCompleted(_ value: Bool) {
        snapshot.firstRunCompleted = value
        scheduleAutosave()
    }

    public func setNotificationsEnabled(_ value: Bool) {
        snapshot.notificationsEnabled = value
        scheduleAutosave()
    }

    public func setLaunchAtLogin(_ value: Bool) {
        snapshot.launchAtLogin = value
        scheduleAutosave()
    }

    public func setAdapterEnabled(_ id: String, enabled: Bool) {
        if enabled {
            snapshot.enabledAdapterIDs.insert(id)
        } else {
            snapshot.enabledAdapterIDs.remove(id)
            if snapshot.preferredAdapterID == id {
                snapshot.preferredAdapterID = snapshot.enabledAdapterIDs.min()
            }
        }
        scheduleAutosave()
    }

    public func setPreferredAdapter(_ id: String?) {
        if let id, !snapshot.enabledAdapterIDs.contains(id) { return }
        snapshot.preferredAdapterID = id
        scheduleAutosave()
    }

    public func setDispatchTimeoutSeconds(_ value: Int) {
        snapshot.dispatchTimeoutSeconds = max(5, min(value, 3600))
        scheduleAutosave()
    }

    public func setPrivacyPolicyAccepted(_ value: Bool) {
        snapshot.privacyPolicyAccepted = value
        scheduleAutosave()
    }

    public func replaceSnapshot(_ next: PreferencesSnapshot) {
        snapshot = next
        scheduleAutosave()
    }

    /// 현재 snapshot 즉시 저장 (debounce 무시).
    public func flush() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        let value = snapshot
        try? await store.save(value)
    }

    // MARK: - Internal

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let nanos = autosaveDebounceNanos
        let value = snapshot
        let store = self.store
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            try? await store.save(value)
        }
    }
}
