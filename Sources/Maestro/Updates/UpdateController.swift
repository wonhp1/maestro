import Foundation
import Sparkle
import SwiftUI

/// Sparkle `SPUStandardUpdaterController` wrapper — MaestroApp 가 한 인스턴스 보유.
///
/// ## 동작
/// - 부팅 시 `SPUStandardUpdaterController(startingUpdater: true, ...)` 자동 시작
/// - Info.plist 의 `SUFeedURL` 에서 appcast.xml fetch (24h 주기 OS 결정)
/// - 새 버전 발견 → Sparkle UI modal 자동 표시 → 사용자 동의 시 다운로드 + 재시작
/// - "Check for Updates…" 메뉴 액션은 `updater.checkForUpdates()` 호출
///
/// ## 보안
/// - Info.plist 의 `SUPublicEDKey` 와 매치하는 EdDSA 서명만 install
/// - HTTPS 만 (Sparkle 내장 검증)
@MainActor
public final class UpdateController {
    private let controller: SPUStandardUpdaterController

    public init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    public var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
