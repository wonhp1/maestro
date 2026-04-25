import Foundation
import MaestroCore

/// Anthropic Claude Code CLI (`claude`) 어댑터.
///
/// ## 통합 (Phase 4-6 인프라)
/// - `CLIDetector` 로 설치 감지 / 버전 추출
/// - `ProcessExecuting` 로 `claude -p ... --output-format json` collected exec
/// - `ProcessStreaming` 로 `claude -p ... --output-format stream-json --verbose` 라인 스트리밍
/// - `EnvironmentSanitizer.default` 로 부모 토큰 leak 차단 (Claude 자체 인증 사용)
///
/// ## 세션 모델
/// - `createSession` 시 새 UUID 발급. 첫 `sendMessage` 까지 CLI spawn 안 함 (cheap).
/// - 첫 호출: `--session-id <uuid>` (Claude 가 새 세션 파일 생성)
/// - 이후 호출: `--resume <uuid>` (Claude 가 기존 세션 파일에 append)
/// - `destroySession`: 메모리에서만 제거. 디스크 세션 파일은 그대로 둠 (사용자가 `claude --resume` 으로 재개 가능).
///
/// ## 슬래시 명령 노출
/// - `ClaudeSlashCommands.builtIns` (정적)
/// - 사용자 정의: `~/.claude/commands/*.md`
/// - 프로젝트 정의: `<folder>/.claude/commands/*.md`
public actor ClaudeAdapter: AgentAdapter {
    public static let id: String = ClaudeProfile.adapterID
    public static let displayName: String = ClaudeProfile.displayName
    public static let iconName: String = "sparkles"

    /// 단일 응답 stdout cap — 악성 child 의 멀티-GB JSON 차단 (Phase 7 sec must-fix).
    private static let maxCollectedOutputBytes = 16 * 1024 * 1024

    private let executor: any ProcessExecuting
    private let streamer: any ProcessStreaming
    private let detector: CLIDetector
    private let profile: AgentProfile
    private let sanitizer: EnvironmentSanitizer
    private let userCommandsDirectory: URL
    private let logger: MaestroLogger
    /// 매 sendMessage 마다 호출 — nil 이면 system prompt 미적용. control agent 가
    /// 동적 폴더 목록 주입에 사용 (Phase 27).
    private let appendSystemPromptProvider: @Sendable () -> String?

    private var sessions: [SessionID: Session] = [:]
    /// 첫 메시지 전송이 완료된 세션 — 이후 호출은 `--resume`.
    private var initializedSessions: Set<SessionID> = []
    /// detect() 결과 캐시 — sendMessage 마다 spawn 비용 제거 (Phase 7 perf must-fix).
    /// processFailed 시 invalidate.
    private var cachedDetection: AdapterDetection?

    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(timeout: 600),
        streamer: any ProcessStreaming = DefaultProcessStreamer(),
        detector: CLIDetector = CLIDetector(),
        executable: String = ClaudeProfile.executableName,
        sanitizer: EnvironmentSanitizer = .default,
        userCommandsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/commands", directoryHint: .isDirectory),
        appendSystemPromptProvider: @escaping @Sendable () -> String? = { nil }
    ) throws {
        self.executor = executor
        self.streamer = streamer
        self.detector = detector
        self.profile = try ClaudeProfile.makeProfile(executable: executable)
        self.sanitizer = sanitizer
        self.userCommandsDirectory = userCommandsDirectory
        self.logger = MaestroLogger(category: .adapter)
        self.appendSystemPromptProvider = appendSystemPromptProvider
    }

    // MARK: - AgentAdapter conformance

    public func detect() async -> AdapterDetection {
        if let cached = cachedDetection { return cached }
        let detection = await detector.detect(profile: profile)
        if detection.isInstalled { cachedDetection = detection }  // 실패는 cache 안 함
        return detection
    }

    /// 외부에서 명시적으로 detect cache 무효화 (CLI 업데이트/이동 후).
    public func invalidateDetectionCache() {
        cachedDetection = nil
    }

    public func createSession(folderPath: URL) async throws -> Session {
        let sessionId = SessionID.new()
        // Phase 7 must-fix: folderPath symlink 사전 해제 — TOCTOU 방지.
        let resolvedFolder = folderPath.resolvingSymlinksInPath()
        let now = Date()
        let session = Session(
            id: sessionId,
            agentId: try AgentID.validated(rawValue: Self.id),
            adapterId: try AdapterID.validated(rawValue: Self.id),
            folderPath: resolvedFolder,
            createdAt: now,
            lastActivityAt: now,
            status: .active
        )
        sessions[sessionId] = session
        logger.info("createSession id=\(sessionId.rawValue) folder=\(resolvedFolder.path)")
        return session
    }

    public func destroySession(_ id: SessionID) async throws {
        guard sessions.removeValue(forKey: id) != nil else {
            throw AdapterError.unknownSession(id: id)
        }
        initializedSessions.remove(id)
        logger.info("destroySession id=\(id.rawValue)")
    }

    public func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        let resolved = try await resolveExecutable(for: session)
        let arguments = buildArguments(
            for: envelope,
            session: session,
            outputFormat: "json"
        )
        let output = try await executor.run(
            executable: resolved,
            arguments: arguments,
            currentDirectoryURL: session.folderPath,
            environment: sanitizer.sanitizedProcessEnvironment()
        )
        guard output.exitCode == 0 else {
            invalidateDetectionCache()  // 실패 시 cache invalidate (CLI 변동 가능성)
            throw AdapterError.processFailed(exitCode: output.exitCode, stderr: output.stderr)
        }
        // Phase 7 sec must-fix: stdout cap 검증 — 악성 child OOM 차단.
        guard output.stdout.utf8.count <= Self.maxCollectedOutputBytes else {
            throw AdapterError.processFailed(
                exitCode: 0,
                stderr: "claude returned >\(Self.maxCollectedOutputBytes) bytes"
            )
        }
        let parsed = try ClaudeJSONResult.decode(from: output.stdout)
        let text = try parsed.validatedResultText()
        initializedSessions.insert(session.id)
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
        let user = ClaudeSlashCommands.scan(directory: userCommandsDirectory, category: "user")
        let projectDir = session.folderPath
            .appending(path: ".claude/commands", directoryHint: .isDirectory)
        let project = ClaudeSlashCommands.scan(directory: projectDir, category: "project")
        return ClaudeSlashCommands.builtIns + user + project
    }

    // MARK: - Internals

    /// streaming 본문 — sendMessage 와 비슷하나 stream-json 라인 별 ResponseChunk 변환.
    private func driveStream(
        _ envelope: MessageEnvelope,
        in session: Session,
        continuation: AsyncThrowingStream<ResponseChunk, Error>.Continuation
    ) async throws {
        let resolved = try await resolveExecutable(for: session)
        let arguments = buildArguments(
            for: envelope,
            session: session,
            outputFormat: "stream-json"
        )
        let stream = streamer.stream(
            executable: resolved,
            arguments: arguments,
            currentDirectoryURL: session.folderPath,
            environment: sanitizer.sanitizedProcessEnvironment()
        )
        var stderrSnippet = ""  // 비정상 종료 시 처음 ~1KB 까지 보존 후 throw 에 포함
        var sawAnyOutput = false
        for try await event in stream {
            switch event.kind {
            case .stdoutLine(let line):
                if !sawAnyOutput {
                    sawAnyOutput = true
                    // Phase 7 must-fix: 첫 stdout 도착 = Claude 가 세션 파일 작성 시작 시점
                    // → cancel/error 시점에도 다음 호출은 --resume 으로 가야 함.
                    initializedSessions.insert(session.id)
                }
                for chunk in ClaudeStreamParser.parse(line: line) {
                    continuation.yield(chunk)
                }
            case .stderrLine(let line):
                logger.warning("claude stderr")
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
    }

    /// detect → executablePath 추출. 미설치 / 알 수 없는 세션 시 throws.
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

    /// 공용 argv 빌더 — 첫 호출 vs resume 분기. stream-json 시 --verbose 자동 포함.
    private func buildArguments(
        for envelope: MessageEnvelope,
        session: Session,
        outputFormat: String
    ) -> [String] {
        let isFirst = !initializedSessions.contains(session.id)
        let sessionFlag = isFirst ? "--session-id" : "--resume"
        var args = [
            "-p", envelope.body,
            sessionFlag, session.id.rawValue,
            "--output-format", outputFormat,
        ]
        if outputFormat == "stream-json" {
            args.append("--verbose")
        }
        // Phase 27 — control agent 처럼 동적 system prompt 주입.
        // 매 호출마다 fresh — 폴더 추가/제거 즉시 반영.
        if let systemPrompt = appendSystemPromptProvider(), !systemPrompt.isEmpty {
            args.append("--append-system-prompt")
            args.append(systemPrompt)
        }
        return args
    }

    // MARK: - Test seam

    /// 테스트가 세션 상태를 검증하기 위한 read-only 접근자.
    public func isInitialized(_ id: SessionID) -> Bool {
        initializedSessions.contains(id)
    }

    public func activeSessionIds() -> [SessionID] {
        Array(sessions.keys)
    }
}
