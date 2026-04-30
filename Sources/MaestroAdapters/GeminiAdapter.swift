import Foundation
import MaestroCore

/// v0.9.0 — Google Gemini CLI (`gemini`) 어댑터.
///
/// ## CodexAdapter 패턴 재사용
/// 두 CLI 모두 NDJSON stream 출력 → 거의 동일 구조. 차이점:
/// - Gemini 는 `-p "<PROMPT>" -o stream-json --skip-trust` 형식
/// - assistant 응답이 `delta:true` chunk 단위로 옴 (vs Codex 의 한 번에 전체)
/// - resume 가 UUID 가 아닌 name/index/`latest` 식별자 사용
/// - OAuth 자동 (`gemini auth login` 명령 X — 첫 실행 시 자동 트리거)
///
/// ## 보안
/// `--skip-trust` 강제 — Maestro 가 폴더 자체를 신뢰 보증.
/// `EnvironmentSanitizer.default` 로 부모 토큰 leak 차단.
public actor GeminiAdapter: AgentAdapter {
    public static let id: String = GeminiProfile.adapterID
    public static let displayName: String = GeminiProfile.displayName
    public static let iconName: String = "sparkle.magnifyingglass"

    private static let maxCollectedOutputBytes = 16 * 1024 * 1024

    private let executor: any ProcessExecuting
    private let streamer: any ProcessStreaming
    private let detector: CLIDetector
    private let profile: AgentProfile
    private let sanitizer: EnvironmentSanitizer
    private let logger: MaestroLogger

    private var sessions: [SessionID: Session] = [:]
    private var initializedSessions: Set<SessionID> = []
    /// Gemini 의 session_id (init event 에서 수신).
    private var geminiSessionIds: [SessionID: String] = [:]
    private var cachedDetection: AdapterDetection?
    private var lastSeenModelBySession: [SessionID: String] = [:]

    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(timeout: 600),
        streamer: any ProcessStreaming = DefaultProcessStreamer(),
        detector: CLIDetector = CLIDetector(),
        executable: String = GeminiProfile.executableName,
        sanitizer: EnvironmentSanitizer = .default
    ) throws {
        self.executor = executor
        self.streamer = streamer
        self.detector = detector
        self.profile = try GeminiProfile.makeProfile(executable: executable)
        self.sanitizer = sanitizer
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
        geminiSessionIds.removeValue(forKey: id)
        lastSeenModelBySession.removeValue(forKey: id)
        logger.info("destroySession id=\(id.rawValue)")
    }

    public func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        let executable = try await resolveExecutable()
        let arguments = buildArguments(prompt: envelope.body, session: session)
        let env = sanitizer.sanitize(ProcessInfo.processInfo.environment)
        let output: ProcessOutput
        do {
            output = try await executor.run(
                executable: executable,
                arguments: arguments,
                currentDirectoryURL: session.folderPath,
                environment: env
            )
        } catch {
            invalidateDetectionCache()
            throw error
        }
        if output.stdout.utf8.count > Self.maxCollectedOutputBytes {
            throw AdapterError.processFailed(
                exitCode: -1,
                stderr: "Gemini stdout exceeded \(Self.maxCollectedOutputBytes) bytes"
            )
        }
        let events = GeminiStreamParser.parseAll(stdout: output.stdout)
        if events.isEmpty {
            let snippet = "stdout=\(output.stdout.prefix(300))|stderr=\(output.stderr.prefix(300))|exit=\(output.exitCode)"
            throw GeminiResponseError.malformedOutput(snippet: snippet)
        }
        if let errMsg = GeminiStreamParser.extractError(events: events) {
            throw GeminiResponseError.geminiReportedError(message: errMsg)
        }
        guard let assistantText = GeminiStreamParser.extractFinalAssistantText(events: events) else {
            throw GeminiResponseError.missingAssistantText(
                snippet: String(output.stdout.prefix(500))
            )
        }
        // session_id / model 캡처
        if let sessionId = GeminiStreamParser.extractSessionId(events: events) {
            geminiSessionIds[session.id] = sessionId
            initializedSessions.insert(session.id)
        }
        if let model = GeminiStreamParser.extractModel(events: events) {
            lastSeenModelBySession[session.id] = model
        }
        return MessageEnvelope.report(
            from: envelope.to,
            inReplyTo: envelope,
            body: assistantText
        )
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

    /// Gemini 는 별도 정적 builtin 명령 카탈로그 X — Phase 4 에서 정의.
    /// 현재는 빈 배열 (사용자 정의 슬래시 명령 시스템 없음).
    public func listSlashCommands(in session: Session) async -> [SlashCommand] {
        []
    }

    /// Gemini 가 `-m <MODEL>` 로 받는 식별자.
    public func availableModels() async -> [String] {
        [
            "gemini-3-flash-preview",
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.0-flash",
        ]
    }

    public func resolvedModel(for session: Session) async -> String? {
        if let lastSeen = lastSeenModelBySession[session.id] { return lastSeen }
        if let explicit = session.modelId, !explicit.isEmpty { return explicit }
        return nil
    }

    public func capturedSlashCommands() async -> [String] {
        []
    }

    // MARK: - Private helpers

    private func driveStream(
        _ envelope: MessageEnvelope,
        in session: Session,
        continuation: AsyncThrowingStream<ResponseChunk, Error>.Continuation
    ) async throws {
        let resolved = try await resolveExecutable()
        let arguments = buildArguments(prompt: envelope.body, session: session)
        let env = sanitizer.sanitize(ProcessInfo.processInfo.environment)
        let stream = streamer.stream(
            executable: resolved,
            arguments: arguments,
            currentDirectoryURL: session.folderPath,
            environment: env
        )
        var stderrSnippet = ""
        var sawAnyOutput = false
        for try await event in stream {
            try await handleStreamEvent(
                event,
                session: session,
                sawAnyOutput: &sawAnyOutput,
                stderrSnippet: &stderrSnippet,
                continuation: continuation
            )
        }
    }

    private func handleStreamEvent(
        _ event: ProcessStreamEvent,
        session: Session,
        sawAnyOutput: inout Bool,
        stderrSnippet: inout String,
        continuation: AsyncThrowingStream<ResponseChunk, Error>.Continuation
    ) async throws {
        switch event.kind {
        case .stdoutLine(let line):
            if !sawAnyOutput {
                sawAnyOutput = true
                initializedSessions.insert(session.id)
            }
            try processStdoutLine(line, session: session, continuation: continuation)
        case .stderrLine(let line):
            logger.warning("gemini stderr")
            if stderrSnippet.utf8.count < 1024 {
                stderrSnippet += line + "\n"
            }
        case .exited(let code, _):
            if code != 0 {
                invalidateDetectionCache()
                throw AdapterError.processFailed(exitCode: code, stderr: stderrSnippet)
            }
        }
    }

    private func processStdoutLine(
        _ line: String,
        session: Session,
        continuation: AsyncThrowingStream<ResponseChunk, Error>.Continuation
    ) throws {
        guard let parsed = GeminiStreamParser.parse(line: line) else { return }
        if parsed.type == "init" {
            if let sessionId = parsed.sessionId {
                geminiSessionIds[session.id] = sessionId
            }
            if let model = parsed.model {
                lastSeenModelBySession[session.id] = model
            }
        }
        if parsed.type == "error", let msg = parsed.message {
            throw GeminiResponseError.geminiReportedError(message: msg)
        }
        for chunk in GeminiStreamParser.chunks(from: parsed) {
            continuation.yield(chunk)
        }
    }

    private func resolveExecutable() async throws -> URL {
        let detection = await detect()
        guard detection.isInstalled, let path = detection.executablePath else {
            throw AdapterError.notInstalled(adapterId: Self.id)
        }
        return path
    }

    /// argv 빌드.
    /// - 첫/후속 호출: `gemini -p "<PROMPT>" -o stream-json --skip-trust [-m MODEL]`
    /// - resume 동작: Gemini 의 `-r latest` 는 최근 세션을 자동 선택하지만 Maestro
    ///   는 명시적 session 관리 — 매 호출마다 같은 cwd 에서 실행해 컨텍스트 유지.
    private func buildArguments(prompt: String, session: Session) -> [String] {
        var args: [String] = ["-p", prompt, "-o", "stream-json", "--skip-trust"]
        if let model = session.modelId, !model.isEmpty {
            args.append(contentsOf: ["-m", model])
        }
        return args
    }

    // MARK: - Test seam (internal)

    func isInitialized(_ id: SessionID) -> Bool {
        initializedSessions.contains(id)
    }

    func activeSessionIds() -> Set<SessionID> {
        Set(sessions.keys)
    }

    func geminiSessionId(for sessionId: SessionID) -> String? {
        geminiSessionIds[sessionId]
    }
}
