import AppKit
import Foundation
import Observation

/// v0.11.0 — VendorPickerSheet 의 인증 / 로그인 로직을 분리한 Observable Coordinator.
///
/// **분리 이유**:
/// - VendorPickerSheet 가 510줄 초과로 file_length lint disable 보유
/// - View 안에 인증 흐름이 갇혀 있어서 단위 테스트 불가능했음 (v0.9.6 critical 회귀가
///   6개 버전 잠복했던 근본 원인)
///
/// **책임**:
/// - codex/gemini 인증 상태 polling (`loadAuth`)
/// - 인앱 OAuth 로그인 dispatch (`performLogin`)
/// - LoginResult 를 사용자 메시지로 변환
/// - 진행 중 Task 핸들 보관 + cancel
///
/// **격리**: `@MainActor` — `loginInProgress` / `loginMessage` 가 SwiftUI 상태
/// (CommentaryView 의 `@Bindable` 로 사용).
@MainActor
@Observable
public final class VendorPickerAuthCoordinator {
    public enum AuthState: Equatable, Sendable {
        case idle
        case checking
        case ready(Bool)
    }

    public private(set) var authStateByAdapter: [String: AuthState] = [:]
    public private(set) var loginInProgress: [String: Bool] = [:]
    public private(set) var loginMessage: [String: String] = [:]
    private var loginTask: Task<Void, Never>?

    private let checker: EnvironmentChecker
    private let locator: any ExecutableLocating
    private let pasteboard: any AuthPasteboard

    public init(
        checker: EnvironmentChecker = EnvironmentChecker(),
        locator: any ExecutableLocating = PATHExecutableLocator(),
        pasteboard: any AuthPasteboard = SystemPasteboard()
    ) {
        self.checker = checker
        self.locator = locator
        self.pasteboard = pasteboard
    }

    // MARK: - 인증 상태 검사

    /// codex/gemini 의 OAuth/API key 인증 상태 검사. 결과를 `authStateByAdapter` 에 반영.
    public func loadAuth(for adapterId: String) async {
        authStateByAdapter[adapterId] = .checking
        let isAuthed: Bool
        switch adapterId {
        case "codex":
            isAuthed = await checker.checkCodexAuth().isReady
        case "gemini":
            isAuthed = await checker.checkGeminiAuth().isReady
        default:
            isAuthed = true
        }
        authStateByAdapter[adapterId] = .ready(isAuthed)
    }

    // MARK: - 인앱 로그인 dispatch

    /// 사용자가 "Maestro 로 로그인" 클릭 시 호출. 진행 중 Task 는 cancel 후 새 Task 생성.
    /// 반환된 Task 를 `await` 하면 테스트가 deterministic — 실 사용에서는 fire-and-forget.
    @discardableResult
    public func startLogin(for adapterId: String) -> Task<Void, Never> {
        loginTask?.cancel()
        let task = Task { await performLogin(for: adapterId) }
        loginTask = task
        return task
    }

    /// sheet 닫힘 시 호출 — 좀비 polling 프로세스 방지.
    public func cancelPendingLogin() {
        loginTask?.cancel()
        loginTask = nil
    }

    // MARK: - Private

    private func performLogin(for adapterId: String) async {
        defer { loginTask = nil }
        let cliName = adapterId
        guard let path = locator.locate(cliName) else {
            loginMessage[adapterId] = "\(cliName) CLI 를 찾을 수 없어요"
            return
        }
        loginInProgress[adapterId] = true
        loginMessage[adapterId] = "브라우저에서 로그인 중…"
        defer { loginInProgress[adapterId] = false }

        let result = await dispatchLogin(for: adapterId, path: path)
        applyResult(result, for: adapterId)
    }

    private func dispatchLogin(
        for adapterId: String,
        path: URL
    ) async -> InteractiveAuthHelper.LoginResult {
        switch adapterId {
        case "codex":
            return await InteractiveAuthHelper.loginCodex(codexPath: path, checker: checker)
        case "gemini":
            return await InteractiveAuthHelper.loginGemini(geminiPath: path, checker: checker)
        default:
            return .processFailed(message: "지원되지 않는 어댑터: \(adapterId)")
        }
    }

    private func applyResult(
        _ result: InteractiveAuthHelper.LoginResult,
        for adapterId: String
    ) {
        switch result {
        case .success:
            loginMessage[adapterId] = "로그인 성공"
            Task { await loadAuth(for: adapterId) }
        case .cancelled:
            loginMessage[adapterId] = "로그인 취소됨"
        case .timedOut:
            loginMessage[adapterId] = "5분 내 로그인 안 됨. 기존 브라우저 탭은 닫고 다시 시도하세요."
        case .processFailed(let m):
            loginMessage[adapterId] = "실패: \(m)"
        case .browserOpenFailed(let url):
            pasteboard.copy(url.absoluteString)
            loginMessage[adapterId] = "브라우저를 열 수 없습니다. URL 을 클립보드에 복사했어요 — 직접 붙여넣어 로그인하세요."
        }
    }
}

/// 클립보드 추상화 — 테스트에서 mock 가능. `Sendable` — 다른 actor 에서 호출 가능해야.
public protocol AuthPasteboard: Sendable {
    func copy(_ string: String)
}

/// `NSPasteboard.general` 은 main thread 에서 호출되어야 안전 — coordinator 가
/// `@MainActor` 라 conformance 자동 충족. struct 라 value-type Sendable 자동 derive.
public struct SystemPasteboard: AuthPasteboard {
    public init() {}
    public func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
