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
    /// v0.5.0 — Session 별 추가 system prompt (예: 토론 메모). 결과는 위 provider
    /// 와 `\n\n` 으로 concat. nil 이면 추가 없음. async — actor 기반 store 호출 가능.
    private let sessionScopedPromptProvider: @Sendable (Session) async -> String?

    private var sessions: [SessionID: Session] = [:]
    /// 첫 메시지 전송이 완료된 세션 — 이후 호출은 `--resume`.
    private var initializedSessions: Set<SessionID> = []
    /// detect() 결과 캐시 — sendMessage 마다 spawn 비용 제거 (Phase 7 perf must-fix).
    /// processFailed 시 invalidate.
    private var cachedDetection: AdapterDetection?
    /// v0.5.2 — 응답에서 capture 한 마지막 모델 ID (예: "claude-sonnet-4-5-20250929").
    /// 사용자가 명시적 modelId 안 줬을 때 UI 가 실제 동작 모델을 표시하기 위함.
    /// 세션별로 추적 — 세션마다 다른 모델일 수 있음.
    private var lastSeenModelBySession: [SessionID: String] = [:]

    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(timeout: 600),
        streamer: any ProcessStreaming = DefaultProcessStreamer(),
        detector: CLIDetector = CLIDetector(),
        executable: String = ClaudeProfile.executableName,
        sanitizer: EnvironmentSanitizer = .default,
        userCommandsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/commands", directoryHint: .isDirectory),
        appendSystemPromptProvider: @escaping @Sendable () -> String? = { nil },
        sessionScopedPromptProvider: @escaping @Sendable (Session) async -> String? = { _ in nil }
    ) throws {
        self.executor = executor
        self.streamer = streamer
        self.detector = detector
        self.profile = try ClaudeProfile.makeProfile(executable: executable)
        self.sanitizer = sanitizer
        self.userCommandsDirectory = userCommandsDirectory
        self.logger = MaestroLogger(category: .adapter)
        self.appendSystemPromptProvider = appendSystemPromptProvider
        self.sessionScopedPromptProvider = sessionScopedPromptProvider
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
        try await createSession(
            folderPath: folderPath, preferredSessionId: nil, modelId: nil
        )
    }

    /// I-NEW-2 fix — preferredSessionId 가 주어지면 그 ID 로 세션을 만들고, 디스크에
    /// 같은 이름의 JSONL 이 이미 있으면 다음 send 부터 자동으로 `--resume <id>` 사용.
    /// (initializedSessions 에 미리 등록 → sendMessage 가 isFirst=false 분기.)
    /// v0.5.1 — modelId 가 주어지면 Session.modelId 에 저장 → buildArguments 가
    /// `--model <id>` flag 추가.
    public func createSession(
        folderPath: URL, preferredSessionId: SessionID?, modelId: String?
    ) async throws -> Session {
        let sessionId = preferredSessionId ?? SessionID.new()
        let resolvedFolder = folderPath.resolvingSymlinksInPath()
        let now = Date()
        let session = Session(
            id: sessionId,
            agentId: try AgentID.validated(rawValue: Self.id),
            adapterId: try AdapterID.validated(rawValue: Self.id),
            folderPath: resolvedFolder,
            createdAt: now,
            lastActivityAt: now,
            status: .active,
            modelId: modelId
        )
        sessions[sessionId] = session
        // preferredSessionId 가 있고 해당 JSONL 이 이미 존재하면 첫 send 부터 --resume.
        if preferredSessionId != nil, sessionFileExists(sessionId, in: resolvedFolder) {
            initializedSessions.insert(sessionId)
            logger.info("createSession resume id=\(sessionId.rawValue) folder=\(resolvedFolder.path)")
        } else {
            logger.info("createSession new id=\(sessionId.rawValue) folder=\(resolvedFolder.path)")
        }
        return session
    }

    /// `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` 존재 여부를 brute-force
    /// 검색. claude 의 경로 인코딩 규칙을 정확히 모르니 최상위 polling 으로 확인.
    private func sessionFileExists(_ id: SessionID, in folder: URL) -> Bool {
        let projectsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects", directoryHint: .isDirectory)
        let target = "\(id.rawValue).jsonl"
        guard let entries = try? FileManager.default.contentsOfDirectory(
            atPath: projectsRoot.path
        ) else { return false }
        for dir in entries {
            let path = projectsRoot.appending(path: dir).appending(path: target)
            if FileManager.default.fileExists(atPath: path.path) { return true }
        }
        return false
    }

    public func destroySession(_ id: SessionID) async throws {
        guard sessions.removeValue(forKey: id) != nil else {
            throw AdapterError.unknownSession(id: id)
        }
        initializedSessions.remove(id)
        lastSeenModelBySession[id] = nil
        logger.info("destroySession id=\(id.rawValue)")
    }

    /// v0.5.2 — 우선순위:
    /// 1. 사용자 지정 session.modelId
    /// 2. 응답에서 capture 한 lastSeen (가장 정확 — Claude Code 의 실제 동작 모델)
    /// 3. Claude Code CLI 의 알려진 default (현재 sonnet 4.5) — 응답 1회 받기 전 표시용
    /// 사용자가 CLI 쪽에서 default 를 바꿨다면 첫 응답 후 lastSeen 으로 자동 정정.
    public func resolvedModel(for session: Session) async -> String? {
        if let explicit = session.modelId, !explicit.isEmpty { return explicit }
        if let lastSeen = lastSeenModelBySession[session.id] { return lastSeen }
        return Self.knownDefaultModel
    }

    /// v0.5.2 — Claude Code CLI 의 stock default. CLI 가 새 모델로 default 옮기면
    /// 여기 + 사용자가 한 번 응답 받으면 자동 capture 가 정정.
    public static let knownDefaultModel = "claude-sonnet-4-5"

    public func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        let resolved = try await resolveExecutable(for: session)
        let arguments = await buildArguments(
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
        // v0.5.2 — 응답의 model 필드 capture → resolvedModel 이 실제 사용 중인 모델
        // (사용자가 명시 안 했더라도) 표시 가능.
        if let model = parsed.model, !model.isEmpty {
            lastSeenModelBySession[session.id] = model
        }
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
        let arguments = await buildArguments(
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
                // v0.5.2 — system.init 라인에서 model capture (사용자가 modelId
                // 명시 안 했을 때 UI 가 정확한 default 표시 가능).
                if let model = ClaudeStreamParser.extractModel(from: line) {
                    lastSeenModelBySession[session.id] = model
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
    /// v0.5.0: async — sessionScopedPromptProvider (메모 store actor) 호출 위해.
    private func buildArguments(
        for envelope: MessageEnvelope,
        session: Session,
        outputFormat: String
    ) async -> [String] {
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
        // v0.5.1 — 폴더 단위 모델 선택 (예: claude-sonnet-4-5, claude-opus-4-1).
        // nil 이면 flag 안 보냄 → Claude CLI 의 default.
        if let modelId = session.modelId, !modelId.isEmpty {
            args.append("--model")
            args.append(modelId)
        }
        // Phase 27 — control agent 처럼 동적 system prompt 주입.
        // 매 호출마다 fresh — 폴더 추가/제거 즉시 반영.
        // v0.5.0: legacy provider + session-scoped (memo) provider 두 source 를
        // `\n\n` 으로 concat. 둘 다 nil/empty 면 flag 자체를 안 보냄.
        var pieces: [String] = []
        if let p = appendSystemPromptProvider(), !p.isEmpty { pieces.append(p) }
        if let p = await sessionScopedPromptProvider(session), !p.isEmpty {
            pieces.append(p)
        }
        if !pieces.isEmpty {
            args.append("--append-system-prompt")
            args.append(pieces.joined(separator: "\n\n"))
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
