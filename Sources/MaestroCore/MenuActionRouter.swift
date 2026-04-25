import Foundation
import Observation

/// SwiftUI `CommandGroup` / `MenuBarExtra` 가 호출하는 메뉴 액션 단일 진입점.
///
/// ## 설계 의도
/// - SwiftUI 의 `Commands` 는 환경 객체 / 의존성을 직접 주입받기 까다롭다.
///   Router 가 weak/optional handler 슬롯을 노출 → 호스트(`MaestroApp` /
///   `ControlTowerEnvironment`) 가 부팅 시 실제 액션을 등록.
/// - 모든 핸들러는 optional — 등록되지 않은 액션은 silently 무시 (에러 toast 없음).
/// - 메뉴 자체의 활성/비활성은 SwiftUI `disabled(...)` 가 처리, Router 는 boolean
///   가능성만 노출.
///
/// ## 동시성
/// `@MainActor @Observable` — SwiftUI 환경에서 자유롭게 binding. 핸들러는 `@Sendable`
/// async closure.
@MainActor
@Observable
public final class MenuActionRouter {
    /// 새 폴더 추가 (NSOpenPanel).
    @ObservationIgnored
    public var onAddFolder: (@Sendable () async -> Void)?
    /// 현재 선택 폴더 제거.
    @ObservationIgnored
    public var onDeleteSelectedFolder: (@Sendable () async -> Void)?
    /// 커맨드 팔레트 열기.
    @ObservationIgnored
    public var onOpenCommandPalette: (@Sendable () async -> Void)?
    /// 환경설정 열기 (Phase 19 에서 채워짐).
    @ObservationIgnored
    public var onOpenPreferences: (@Sendable () async -> Void)?
    /// 데이터 폴더 열기 (Finder).
    @ObservationIgnored
    public var onRevealDataFolder: (@Sendable () async -> Void)?
    /// 진단 번들 생성.
    @ObservationIgnored
    public var onExportDiagnostics: (@Sendable () async -> Void)?

    /// 보고서 / 도움 페이지 — Phase 19+ 에서 wiring.
    @ObservationIgnored
    public var onOpenHelp: (@Sendable () async -> Void)?

    public var canDeleteSelectedFolder: Bool = false

    public init() {}

    // MARK: - 호출 진입점 (Commands view 에서 호출)

    public func addFolder() {
        guard let handler = onAddFolder else { return }
        Task { await handler() }
    }

    public func deleteSelectedFolder() {
        guard canDeleteSelectedFolder, let handler = onDeleteSelectedFolder else { return }
        Task { await handler() }
    }

    public func openCommandPalette() {
        guard let handler = onOpenCommandPalette else { return }
        Task { await handler() }
    }

    public func openPreferences() {
        guard let handler = onOpenPreferences else { return }
        Task { await handler() }
    }

    public func revealDataFolder() {
        guard let handler = onRevealDataFolder else { return }
        Task { await handler() }
    }

    public func exportDiagnostics() {
        guard let handler = onExportDiagnostics else { return }
        Task { await handler() }
    }

    public func openHelp() {
        guard let handler = onOpenHelp else { return }
        Task { await handler() }
    }
}
