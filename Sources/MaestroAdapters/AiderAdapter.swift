import Foundation
import MaestroCore

/// Aider CLI (`aider`) 어댑터 — Maestro 의 두 번째 벤더 (BYOA 컨셉 증명).
///
/// ## ClaudeAdapter 와의 차이
/// - **JSON 모드 없음**: Aider 는 `--no-pretty` plain stdout 만 — `AiderOutputParser` 가 휴리스틱 추출.
/// - **세션 = chat history 파일**: Claude 의 `--session-id` 같은 native 세션 식별자 없음.
///   Maestro 가 세션별 `.aider.chat.history.md` 경로 발급 (AppSupport 안에 격리).
/// - **슬래시 명령**: 사용자 정의 시스템 없음 — built-in 정적 목록만.
///
/// ## 보안
/// - `EnvironmentSanitizer.default` 강제 — Aider 는 자체 config / 환경 변수 (`OPENAI_API_KEY`,
///   `ANTHROPIC_API_KEY`) 로 인증. Maestro 는 부모의 토큰을 자식에 leak 안 시킴 → 사용자가
///   별도 환경 / config 로 Aider auth 설정해야 함 (의도적).
public actor AiderAdapter: AgentAdapter {
    public static let id: String = AiderProfile.adapterID
    public static let displayName: String = AiderProfile.displayName
    public static let iconName: String = "wand.and.stars"

    /// 단일 응답 stdout cap — 악성 LLM OOM 차단.
    private static let maxCollectedOutputBytes = 16 * 1024 * 1024

    private let executor: any ProcessExecuting
    private let streamer: any ProcessStreaming
    private let detector: CLIDetector
    private let profile: AgentProfile
    private let sanitizer: EnvironmentSanitizer
    private let chatHistoryRoot: URL
    private let logger: MaestroLogger

    private var sessions: [SessionID: Session] = [:]
    /// session id → chat history 파일 경로 (Aider --chat-history-file 인자).
    private var chatHistoryPaths: [SessionID: URL] = [:]
    private var cachedDetection: AdapterDetection?
    /// v0.6.0 — 응답에서 capture 한 마지막 모델 ID (예: "gpt-4o", "claude-sonnet-4-5").
    /// stdout 의 `Main model: <id>` 라인에서 추출. 사용자가 명시적 modelId 안 줬을
    /// 때 UI 가 실제 동작 모델 표시.
    private var lastSeenModelBySession: [SessionID: String] = [:]

    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(timeout: 600),
        streamer: any ProcessStreaming = DefaultProcessStreamer(),
        detector: CLIDetector = CLIDetector(),
        executable: String = AiderProfile.executableName,
        sanitizer: EnvironmentSanitizer = .default,
        chatHistoryRoot: URL = AiderAdapter.defaultChatHistoryRoot()
    ) throws {
        self.executor = executor
        self.streamer = streamer
        self.detector = detector
        self.profile = try AiderProfile.makeProfile(executable: executable)
        self.sanitizer = sanitizer
        self.chatHistoryRoot = chatHistoryRoot
        self.logger = MaestroLogger(category: .adapter)
    }

    // MARK: - AgentAdapter conformance

    public func detect() async -> AdapterDetection {
        if let cached = cachedDetection { return cached }
        let detection = await detector.detect(profile: profile)
        if detection.isInstalled { cachedDetection = detection }
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

    /// v0.6.0 — modelId 가 주어지면 session.modelId 에 저장 → buildArguments 가
    /// `--model <id>` flag 추가. preferredSessionId 는 Aider 가 native session ID
    /// 미지원이라 무시 (chat history 파일이 사실상 session 식별자).
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
        // 세션별 history 파일 생성 — AppSupport/aider/sessions/<id>.md
        try FileManager.default.createDirectory(
            at: chatHistoryRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let historyURL = chatHistoryRoot.appending(path: "\(sessionId.rawValue).md")
        // Phase 9 sec must-fix: 파일을 0600 으로 미리 생성 — Aider 가 default umask 로
        // 0644 만들지 못하게 (chat history 가 시크릿 포함 가능).
        if !FileManager.default.fileExists(atPath: historyURL.path) {
            FileManager.default.createFile(
                atPath: historyURL.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
            )
        }
        chatHistoryPaths[sessionId] = historyURL
        sessions[sessionId] = session
        logger.info("createSession id=\(sessionId.rawValue)")
        return session
    }

    public func destroySession(_ id: SessionID) async throws {
        guard sessions.removeValue(forKey: id) != nil else {
            throw AdapterError.unknownSession(id: id)
        }
        // history 파일은 보존 — 사용자가 외부에서 `aider --chat-history-file ...` 으로 재개 가능.
        chatHistoryPaths.removeValue(forKey: id)
        lastSeenModelBySession.removeValue(forKey: id)
        logger.info("destroySession id=\(id.rawValue)")
    }

    /// v0.6.0 — Aider 가 흔히 쓰는 stable alias. full version 은 응답에서 capture.
    /// LiteLLM (Aider 의 backend) 가 인식하는 prefix-based 식별자. 사용자 환경에서
    /// 어떤 게 작동할지는 API key 보유 여부에 의존 — 어댑터는 list 만 제공.
    public func availableModels() async -> [String] {
        [
            "gpt-4o",
            "gpt-4o-mini",
            "claude-sonnet-4-5",
            "claude-opus-4-1",
            "claude-haiku-4-5",
            "deepseek-coder",
            "gemini/gemini-2.0-flash",
        ]
    }

    /// v0.6.0 — 우선순위:
    /// 1. 응답에서 capture 한 lastSeen (가장 정확 — 실제 LiteLLM 이 매핑한 model)
    /// 2. 사용자 지정 session.modelId (응답 받기 전 fallback)
    /// 3. nil — UI 가 "감지 중…"
    public func resolvedModel(for session: Session) async -> String? {
        if let lastSeen = lastSeenModelBySession[session.id] { return lastSeen }
        if let explicit = session.modelId, !explicit.isEmpty { return explicit }
        return nil
    }

    public func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        let resolved = try await resolveExecutable(for: session)
        let arguments = try buildArguments(for: envelope, session: session, streaming: false)
        let output = try await executor.run(
            executable: resolved,
            arguments: arguments,
            currentDirectoryURL: session.folderPath,
            environment: sanitizer.sanitizedProcessEnvironment()
        )
        guard output.exitCode == 0 else {
            invalidateDetectionCache()
            throw AdapterError.processFailed(exitCode: output.exitCode, stderr: output.stderr)
        }
        guard output.stdout.utf8.count <= Self.maxCollectedOutputBytes else {
            throw AdapterError.processFailed(
                exitCode: 0,
                stderr: "aider returned >\(Self.maxCollectedOutputBytes) bytes"
            )
        }
        if let knownError = AiderOutputParser.detectKnownError(in: output.stdout) {
            throw AdapterError.processFailed(exitCode: 0, stderr: "aider error: \(knownError)")
        }
        // v0.6.0 — `Main model: <id>` 라인에서 model capture.
        if let model = AiderModelExtractor.extractFromStdout(output.stdout) {
            lastSeenModelBySession[session.id] = model
        }
        let text = AiderOutputParser.extractAssistantResponse(from: output.stdout)
        return MessageEnvelope.report(from: envelope.to, inReplyTo: envelope, body: text)
    }

    nonisolated public func streamMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) -> AsyncThrowingStream<ResponseChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.driveStream(envelope, in: session, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listSlashCommands(in session: Session) async -> [SlashCommand] {
        AiderSlashCommands.builtIns
    }

    // MARK: - Internals

    /// streaming — Aider 의 텍스트 출력을 라인 단위로 받아 휴리스틱하게 .text chunk emit.
    private func driveStream(
        _ envelope: MessageEnvelope,
        in session: Session,
        continuation: AsyncThrowingStream<ResponseChunk, Error>.Continuation
    ) async throws {
        let resolved = try await resolveExecutable(for: session)
        let arguments = try buildArguments(for: envelope, session: session, streaming: true)
        let stream = streamer.stream(
            executable: resolved,
            arguments: arguments,
            currentDirectoryURL: session.folderPath,
            environment: sanitizer.sanitizedProcessEnvironment()
        )
        var state = StreamState()
        for try await event in stream {
            try handleStreamEvent(event, state: &state, continuation: continuation)
        }
        // v0.6.0 — stream 종료 후 누적 stdout 에서 model capture (state.allStdout 가
        // 1MiB cap 내에서 header 라인 포함 보존).
        if let model = AiderModelExtractor.extractFromStdout(state.allStdout) {
            lastSeenModelBySession[session.id] = model
        }
    }

    /// streaming 진행 상태 — driveStream 분리.
    private struct StreamState {
        var stderrSnippet = ""
        var inResponseBody = false
        var emittedAny = false
        var allStdout = ""  // fallback 용 — 한도 1 MiB
    }

    private func handleStreamEvent(
        _ event: ProcessStreamEvent,
        state: inout StreamState,
        continuation: AsyncThrowingStream<ResponseChunk, Error>.Continuation
    ) throws {
        switch event.kind {
        case .stdoutLine(let line):
            handleStdoutLine(line, state: &state, continuation: continuation)
        case .stderrLine(let line):
            logger.warning("aider stderr")
            if state.stderrSnippet.utf8.count < 1024 {
                state.stderrSnippet += line + "\n"
            }
        case .exited(let code, _):
            try handleExit(code: code, state: state, continuation: continuation)
        }
    }

    private func handleStdoutLine(
        _ line: String,
        state: inout StreamState,
        continuation: AsyncThrowingStream<ResponseChunk, Error>.Continuation
    ) {
        if state.allStdout.utf8.count < 1_048_576 {
            state.allStdout += line + "\n"
        }
        if AiderOutputParser.isHeaderOrFooter(line) { return }
        if line.hasPrefix("> ") {
            state.inResponseBody = true
            return
        }
        if state.inResponseBody {
            continuation.yield(.text(line))
            state.emittedAny = true
        }
    }

    private func handleExit(
        code: Int32,
        state: StreamState,
        continuation: AsyncThrowingStream<ResponseChunk, Error>.Continuation
    ) throws {
        if code != 0 {
            invalidateDetectionCache()
            throw AdapterError.processFailed(exitCode: code, stderr: state.stderrSnippet)
        }
        if !state.emittedAny {
            let fallback = AiderOutputParser.extractAssistantResponse(from: state.allStdout)
            if !fallback.isEmpty {
                continuation.yield(.text(fallback))
            }
        }
        continuation.yield(.completion())
    }

    private func resolveExecutable(for session: Session) async throws -> URL {
        guard sessions[session.id] != nil else {
            throw AdapterError.unknownSession(id: session.id)
        }
        let detection = await detect()
        guard detection.isInstalled, let path = detection.executablePath else {
            throw AdapterError.notInstalled(adapterId: Self.id)
        }
        return path
    }

    /// argv 빌더. streaming 여부에 따라 `--no-stream` 토글.
    /// - Phase 9 sec must-fix: Aider 의 `.aider.conf.yml` auto-load + `--yes-always` 결합이
    ///   untrusted folder 에서 RCE 벡터. `--no-auto-lint`/`--no-auto-test`/
    ///   `--no-suggest-shell-commands` 로 자동 실행 path 차단.
    /// - chatHistoryPath 누락 시 `unknownSession` throws — silent fallback 금지.
    private func buildArguments(
        for envelope: MessageEnvelope,
        session: Session,
        streaming: Bool
    ) throws -> [String] {
        guard let historyPath = chatHistoryPaths[session.id]?.path else {
            throw AdapterError.unknownSession(id: session.id)
        }
        var args = [
            "--message", envelope.body,
            "--no-auto-commits",
            "--no-auto-lint",
            "--no-auto-test",
            "--no-suggest-shell-commands",
            "--no-pretty",
            "--yes-always",
            "--no-show-model-warnings",
            "--no-check-update",
        ]
        if !streaming {
            args.append("--no-stream")
        }
        args.append(contentsOf: ["--chat-history-file", historyPath])
        // v0.6.0 — 사용자가 폴더 설정에서 모델 명시 시 `--model <id>` flag.
        // 빈 값/nil 이면 Aider 가 환경변수/config 로 결정 (기본).
        if let modelId = session.modelId, !modelId.isEmpty {
            args.append(contentsOf: ["--model", modelId])
        }
        return args
    }

    // MARK: - Test seam

    public func activeSessionIds() -> [SessionID] {
        Array(sessions.keys)
    }

    public func chatHistoryPath(for sessionID: SessionID) -> URL? {
        chatHistoryPaths[sessionID]
    }

    /// 기본 chat history 저장 위치 — `~/Library/Application Support/Maestro/adapters/aider/sessions/`.
    /// AppSupport 접근 실패 시 temp directory 폴백.
    public static func defaultChatHistoryRoot() -> URL {
        let fallback = FileManager.default.temporaryDirectory
            .appending(path: "maestro-aider-sessions", directoryHint: .isDirectory)
        guard let paths = try? AppSupportPaths.forApplication() else {
            return fallback
        }
        return paths.root
            .appending(path: "adapters/aider/sessions", directoryHint: .isDirectory)
    }
}

// MARK: - Header/footer detection (exposed for streaming path)

extension AiderOutputParser {
    /// 라인이 Aider 의 알려진 헤더 또는 footer 인지 판단 — streaming 시 스킵용.
    static func isHeaderOrFooter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let prefixes = [
            "Aider v", "Main model:", "Weak model:", "Editor model:",
            "Git repo:", "Repo-map:", "Added ", "Tokens:", "Cost:",
            "VSCode:", "Update:", "Commit ", "Applied edit to",
            "Use /help", "Use --help",
        ]
        return prefixes.contains { trimmed.hasPrefix($0) }
    }
}
