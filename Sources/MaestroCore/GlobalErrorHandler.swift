import Foundation

/// 앱 전역 에러 hook.
///
/// 책임:
/// - **NSException**: ObjC/Cocoa 코드에서 던지는 uncaught exception 을 OSLog 로 흘림.
/// - **Swift Error 보조**: 호출자가 `log(_:)` 로 명시 기록 (Swift `Error` 는 자동 hook 불가).
///
/// SwiftUI 앱 부팅 시 `GlobalErrorHandler.install()` 호출. 멱등 — 두 번 호출되면 두 번째는 no-op.
///
/// ## Sparkle / 다른 라이브러리와의 공존 (Phase 21)
/// `install()` 시점의 기존 핸들러를 보존해 chain. Sparkle 같은 다른 라이브러리가
/// **나중에** 핸들러를 install 하면 그쪽이 chain head 가 됨. 우리 핸들러는 그 chain
/// 안에서 호출됨. 따라서 install 순서: **Maestro → Sparkle → 다른 lib**.
///
/// `uninstall()` 은 **테스트 격리 전용**이며, Sparkle 등이 이미 install 했다면
/// 그 핸들러를 통째로 덮어씀 — 운영에서 호출 금지.
public enum GlobalErrorHandler {
    private static let lock = NSLock()
    /// NSLock 으로 직렬화 → safe. Swift 6 의 mutable global 경고를 명시적으로 silence.
    nonisolated(unsafe) private static var installed = false
    /// install() 시점의 기존 핸들러 보존 (chain). C function pointer.
    nonisolated(unsafe) private static var previousHandler: (@convention(c) (NSException) -> Void)?

    /// 1회만 등록되는 NSException 핸들러 설치. 중복 호출 안전.
    public static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true

        // 기존 핸들러 보존 — 다른 라이브러리 (e.g., Sparkle) 가 설치한 것 chain.
        previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(uncaughtHandler)
    }

    /// C function pointer 로 호환 — context capture 없음.
    private static let uncaughtHandler: @convention(c) (NSException) -> Void = { exception in
        let logger = MaestroLogger(category: .general)
        let name = exception.name.rawValue
        let reason = exception.reason ?? "<no reason>"
        logger.fault("Uncaught NSException name=\(name) reason=\(reason)")
        GlobalErrorHandler.previousHandler?(exception)
    }

    /// **테스트 전용** 등록 해제. 운영에서 호출 시 Sparkle 등 다른 핸들러를 덮어쓸 수 있음.
    ///
    /// - Warning: production 호출 금지 — 멀티 라이브러리 chain 을 망가뜨림.
    public static func uninstall() {
        lock.lock()
        defer { lock.unlock() }
        installed = false
        NSSetUncaughtExceptionHandler(previousHandler)
        previousHandler = nil
    }

    /// Swift `Error` 를 카테고리와 함께 로그. 호출자 위치 자동 캡처.
    /// Logger 는 카테고리별 캐시 (Phase 5 perf must-fix) — 매 호출 alloc 없음.
    public static func log(
        _ error: Error,
        category: LogCategory = .general,
        file: String = #fileID,
        line: Int = #line
    ) {
        // MaestroLogger 자체가 내부에서 os.Logger 캐시 — 여기선 wrapper 가벼움.
        let logger = MaestroLogger(category: category)
        logger.error("Error at \(file):\(line) — \(String(describing: error))")
    }
}
