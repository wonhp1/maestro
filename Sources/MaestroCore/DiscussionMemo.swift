import Foundation

/// v0.5.0 — 토론 결론을 자식 에이전트들의 영구 컨텍스트로 만드는 단일 .md 메모.
///
/// ## 설계 배경 (옵션 C)
/// 결론 공유 (Phase 4) 는 자식 메인 세션에 메시지 한 번 typing — 자식이 그 턴에서만
/// 기억함. claude --resume 으로 같은 세션을 재개해도 LLM 의 implicit context 누락
/// 위험. 영구 메모 layer 는 매 sendMessage 마다 메모 본문을 `--append-system-prompt`
/// 로 주입 → LLM 이 항상 결론을 컨텍스트로 갖게 됨.
///
/// **사용자 폴더 invasive X**: CLAUDE.md / ROLE.md 안 건드리고 별도 디렉토리
/// (`~/Library/Application Support/Maestro/discussion-memos/<id>.md`) 에 보관.
///
/// ## 디스크 포맷 (YAML-lite frontmatter + body)
/// ```
/// ---
/// discussionId: <ThreadID>
/// title: <topic>
/// sharedWith: ["agent-{folder-uuid}", ...]
/// updatedAt: 2026-04-27T10:00:00Z
/// active: true
/// ---
///
/// <body — 보통 결론 텍스트, 사용자 편집 가능>
/// ```
public struct DiscussionMemo: Hashable, Sendable, Identifiable {
    public let id: ThreadID
    public var title: String
    public var body: String
    public var sharedWith: [AgentID]
    public var updatedAt: Date
    /// false 이면 systemPrompt 주입 대상 제외 (사용자가 일시 비활성화 — 메모 자체는
    /// 디스크에 보존). 삭제는 store.delete 사용.
    public var active: Bool

    public init(
        id: ThreadID,
        title: String,
        body: String,
        sharedWith: [AgentID],
        updatedAt: Date = Date(),
        active: Bool = true
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.sharedWith = sharedWith
        self.updatedAt = updatedAt
        self.active = active
    }
}

public enum DiscussionMemoError: Error, Equatable, Sendable {
    case malformedFrontmatter
    case missingRequiredField(String)
}
