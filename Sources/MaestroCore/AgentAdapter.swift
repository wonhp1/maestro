import Foundation

/// **Maestro 의 핵심 추상화** — 모든 AI 코딩 에이전트(Claude, Aider, Cursor, ...)가
/// 따르는 공통 프로토콜. BYOA 철학의 기술적 표현.
///
/// 어댑터는 다음을 캡슐화한다:
/// - 시스템에서 자신의 CLI 가 사용 가능한지 감지 (`detect`)
/// - 폴더 컨텍스트에 묶인 세션의 생성/소멸 (`createSession` / `destroySession`)
/// - 메시지 송수신 (단발 `sendMessage` 또는 스트리밍 `streamMessage`)
/// - 슬래시 명령 카탈로그 노출 (`listSlashCommands`)
///
/// 구현체는 **Sendable** 이어야 하며, 보통 actor 또는 immutable struct 형태.
///
/// - SeeAlso: `AdapterRegistry` (런타임 어댑터 관리)
/// - SeeAlso: `MessageEnvelope` (입출력 봉투)
/// - SeeAlso: `Session` (수명 관리되는 CLI 인스턴스)
public protocol AgentAdapter: Sendable {
    /// 어댑터 식별자 (`"claude"`, `"aider"`). URL-safe 짧은 문자열.
    static var id: String { get }
    /// 사람이 읽는 표시명 (`"Claude Code"`).
    static var displayName: String { get }
    /// SF Symbol 이름. UI 가 활용. 비어있어도 무방하나 권장.
    static var iconName: String { get }

    /// 인스턴스 접근자 — 프로토콜 witness 테이블에 포함되어 동적 dispatch.
    /// 기본 구현은 `Self.id` 반환. 동적 id 가 필요한 어댑터는 override.
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }

    /// CLI 설치 여부 + 버전 감지. 절대 throws 하지 않으며, 실패 시 `notInstalled` 반환.
    func detect() async -> AdapterDetection

    /// 폴더 컨텍스트로 새 세션 생성. 어댑터가 CLI 프로세스 spawn 또는 세션 메타 등록.
    func createSession(folderPath: URL) async throws -> Session

    /// 세션 종료. 자식 프로세스/리소스 정리.
    func destroySession(_ id: SessionID) async throws

    /// 단발 메시지 전송 — 응답 envelope 한 건 회수.
    func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope

    /// 스트리밍 메시지 전송 — 청크 단위로 점진적 응답.
    /// 기본 구현은 `sendMessage` 위에 있는 single-chunk fallback.
    func streamMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) -> AsyncThrowingStream<ResponseChunk, Error>

    /// 세션 컨텍스트에서 사용 가능한 슬래시 명령. 기본 구현은 빈 배열.
    func listSlashCommands(in session: Session) async -> [SlashCommand]
}

// MARK: - Default implementations

public extension AgentAdapter {
    /// 기본 인스턴스 접근자 — 정적 값을 그대로 노출.
    var id: String { Self.id }
    var displayName: String { Self.displayName }
    var iconName: String { Self.iconName }

    /// 기본 구현: `sendMessage` 결과를 단일 텍스트 청크 + completion 으로 변환.
    ///
    /// - Warning: **텍스트 전용 어댑터에만 적합.** 도구 호출 / extended thinking /
    ///   mid-stream error 같은 구조화된 청크를 발행해야 하는 어댑터 (예: Phase 7
    ///   ClaudeAdapter) 는 반드시 이 메서드를 override 하여 `ResponseChunk.Kind`
    ///   의 모든 케이스를 적절히 분배해야 한다. 기본 구현은 모든 응답을 `.text` 로
    ///   평탄화시킨다.
    func streamMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) -> AsyncThrowingStream<ResponseChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await sendMessage(envelope, in: session)
                    continuation.yield(ResponseChunk.text(response.body))
                    continuation.yield(ResponseChunk.completion())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 기본 구현: 슬래시 명령 없음. 어댑터가 동적 카탈로그를 가지면 오버라이드.
    func listSlashCommands(in session: Session) async -> [SlashCommand] { [] }

    /// 기본 아이콘 — 미설정 어댑터용 fallback.
    static var iconName: String { "terminal" }
}

// MARK: - Errors

/// 어댑터 공통 에러. 구현체별 에러는 별도 정의 가능.
public enum AdapterError: Error, Equatable, Sendable {
    /// CLI 가 설치되어 있지 않거나 PATH 에서 찾을 수 없음.
    case notInstalled(adapterId: String)
    /// 세션 생성 실패 — 사유 메시지 동봉.
    case sessionCreationFailed(reason: String)
    /// 알 수 없는 세션 ID.
    case unknownSession(id: SessionID)
    /// CLI 가 비정상 종료 (signal 또는 non-zero exit).
    case processFailed(exitCode: Int32, stderr: String)
    /// 어댑터가 해당 작업을 지원하지 않음.
    case unsupported(operation: String)
}
