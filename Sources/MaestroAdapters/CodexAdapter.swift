import Foundation
import MaestroCore

/// v0.9.0 — OpenAI Codex CLI (`codex`) 어댑터.
///
/// ## 통합
/// - `CLIDetector` 로 설치 감지 / 버전 추출
/// - `ProcessExecuting` 로 `codex exec [PROMPT] --json` collected exec (Phase 2B)
/// - `ProcessStreaming` 로 `codex exec --json` 라인 스트리밍 (Phase 2C)
/// - `EnvironmentSanitizer.default` 로 부모 토큰 leak 차단
///   - 단, OAuth 사용 시 ChatGPT Plus/Pro 구독 토큰은 `~/.codex/` 에서 codex CLI 가 직접 로드
///   - API key 모드는 사용자가 별도 환경 또는 `codex login --with-api-key` 설정
///
/// ## 세션 모델
/// - `createSession` 시 새 UUID 발급. 첫 `sendMessage` 까지 CLI spawn 안 함 (cheap).
/// - 첫 호출: `codex exec [PROMPT] --json` (새 thread 생성 → thread.started event 에서 ID 받음)
/// - 이후 호출: `codex exec resume <THREAD_UUID> [PROMPT] --json` (Phase 2B)
/// - `destroySession`: 메모리에서만 제거. ~/.codex/ 의 thread 파일은 보존.
///
/// ## Phase 2A 범위
/// 이 파일은 Phase 2A (skeleton) — `detect`, `createSession`, `destroySession`,
/// `availableModels`, `resolvedModel` 만 동작. `sendMessage` / `streamMessage` /
/// `listSlashCommands` / `capturedSlashCommands` 는 Phase 2B/2C/2D 에서 구현.
///
/// ## 보안
/// `sandbox: workspace-write` 기본 (Maestro 가 사용자에게 폴더 노출 시 적용 예정).
/// `--skip-git-repo-check` — git repo 외부에서도 동작 허용.
public actor CodexAdapter: AgentAdapter {
    public static let id: String = CodexProfile.adapterID
    public static let displayName: String = CodexProfile.displayName
    public static let iconName: String = "cpu"

    /// 단일 응답 stdout cap — 악성 child 의 멀티-GB JSON 차단 (ClaudeAdapter 패턴).
    private static let maxCollectedOutputBytes = 16 * 1024 * 1024

    private let executor: any ProcessExecuting
    private let streamer: any ProcessStreaming
    private let detector: CLIDetector
    private let profile: AgentProfile
    private let sanitizer: EnvironmentSanitizer
    private let logger: MaestroLogger

    private var sessions: [SessionID: Session] = [:]
    /// 첫 메시지 전송이 완료된 세션 — 이후 호출은 `exec resume <thread_id>`.
    private var initializedSessions: Set<SessionID> = []
    /// session id → codex thread_id (UUID, thread.started event 에서 수신).
    private var threadIds: [SessionID: String] = [:]
    /// detect() 결과 캐시 — sendMessage 마다 spawn 비용 제거.
    private var cachedDetection: AdapterDetection?
    /// 응답에서 capture 한 마지막 모델 ID. 사용자가 명시적 modelId 안 줬을 때 UI 가
    /// 실제 동작 모델 표시. 세션별 추적.
    private var lastSeenModelBySession: [SessionID: String] = [:]
    /// v0.7.0 패턴 — codex CLI 가 응답에서 노출하는 builtin slash commands list.
    /// Phase 2D 에서 stream parser 가 채움.
    private var anySessionSlashCommands: [String] = []

    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(timeout: 600),
        streamer: any ProcessStreaming = DefaultProcessStreamer(),
        detector: CLIDetector = CLIDetector(),
        executable: String = CodexProfile.executableName,
        sanitizer: EnvironmentSanitizer = .default
    ) throws {
        self.executor = executor
        self.streamer = streamer
        self.detector = detector
        self.profile = try CodexProfile.makeProfile(executable: executable)
        self.sanitizer = sanitizer
        self.logger = MaestroLogger(category: .adapter)
    }

    // MARK: - AgentAdapter conformance

    public func detect() async -> AdapterDetection {
        if let cached = cachedDetection { return cached }
        let detection = await detector.detect(profile: profile)
        if detection.isInstalled { cachedDetection = detection }  // 실패는 cache 안 함
        return detection
    }

    public func invalidateDetectionCache() {
        cachedDetection = nil
    }

    public func createSession(folderPath: URL) async throws -> Session {
        try await createSession(
            folderPath: folderPath, preferredSessionId: nil, modelId: nil
        )
    }

    public func createSession(
        folderPath: URL, preferredSessionId: SessionID?, modelId: String?
    ) async throws -> Session {
        let sessionId = preferredSessionId ?? SessionID.new()
        let resolved = folderPath.resolvingSymlinksInPath()
        let now = Date()
        let session = Session(
            id: sessionId,
            agentId: try AgentID.validated(rawValue: Self.id),
            adapterId: try AdapterID.validated(rawValue: Self.id),
            folderPath: resolved,
            createdAt: now,
            lastActivityAt: now,
            status: .active,
            modelId: modelId
        )
        sessions[sessionId] = session
        logger.info("createSession id=\(sessionId.rawValue)")
        return session
    }

    public func destroySession(_ id: SessionID) async throws {
        guard sessions.removeValue(forKey: id) != nil else {
            throw AdapterError.unknownSession(id: id)
        }
        initializedSessions.remove(id)
        threadIds.removeValue(forKey: id)
        lastSeenModelBySession.removeValue(forKey: id)
        logger.info("destroySession id=\(id.rawValue)")
    }

    /// Phase 2B 에서 구현 — 현재는 unsupported throw.
    public func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        throw AdapterError.unsupported(operation: "CodexAdapter.sendMessage (Phase 2B)")
    }

    /// Phase 2D 에서 구현 — 현재는 빈 배열.
    public func listSlashCommands(in session: Session) async -> [SlashCommand] {
        []
    }

    /// 알려진 OpenAI 모델 alias (Phase 2D 에서 검증 / 보강).
    /// Codex CLI 가 `-m <MODEL>` 로 받는 식별자.
    public func availableModels() async -> [String] {
        [
            "o1-preview",
            "o1-mini",
            "gpt-5",
            "gpt-5-mini",
            "gpt-4o",
            "gpt-4o-mini",
        ]
    }

    /// 우선순위:
    /// 1. 응답에서 capture 한 lastSeen
    /// 2. 사용자 지정 session.modelId
    /// 3. nil
    public func resolvedModel(for session: Session) async -> String? {
        if let lastSeen = lastSeenModelBySession[session.id] { return lastSeen }
        if let explicit = session.modelId, !explicit.isEmpty { return explicit }
        return nil
    }

    /// Phase 2D 에서 구현.
    public func capturedSlashCommands() async -> [String] {
        anySessionSlashCommands
    }

    // MARK: - Test seam (internal)

    /// 테스트가 internal state 검사 — 외부 사용 X.
    func isInitialized(_ id: SessionID) -> Bool {
        initializedSessions.contains(id)
    }

    func activeSessionIds() -> Set<SessionID> {
        Set(sessions.keys)
    }

    func threadId(for sessionId: SessionID) -> String? {
        threadIds[sessionId]
    }
}
