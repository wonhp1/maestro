import Foundation

/// v0.5.4 — 디스크에 저장되는 토론 한 건의 영속 표현.
///
/// `Discussion` (메타) + 발언 envelope 들을 묶음. 앱 재시작 후 복원 시 사용.
///
/// envelope 들도 같이 보관하는 이유:
/// - threads/<id>.jsonl 에 ThreadLogger 가 envelope 을 append 하지만, jsonl 은
///   message log (multi-thread) 로 설계됐고 토론 viewModel 의 envelopes 와
///   1:1 매핑은 보장 안 됨 (turn metadata + envelope body 각각 분리 저장).
/// - per-discussion JSON 으로 자체 완결적 — sidebar 에서 클릭 → 즉시 복원.
public struct DiscussionRecord: Codable, Hashable, Sendable, Identifiable {
    public let discussion: Discussion
    public let envelopes: [MessageEnvelope]
    public let updatedAt: Date

    public var id: ThreadID { discussion.id }

    public init(
        discussion: Discussion,
        envelopes: [MessageEnvelope],
        updatedAt: Date = Date()
    ) {
        self.discussion = discussion
        self.envelopes = envelopes
        self.updatedAt = updatedAt
    }
}
