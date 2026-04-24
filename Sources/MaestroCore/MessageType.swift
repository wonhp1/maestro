/// 메시지 봉투의 목적/성격 분류.
///
/// - `task`: 상대가 **수행**해야 할 작업 지시. 보통 응답 기대.
/// - `question`: 답변을 요구하는 질의.
/// - `report`: 이전 `task` 에 대한 보고/응답.
/// - `fyi`: 단순 공유. 응답 불필요.
public enum MessageType: String, Codable, Hashable, Sendable, CaseIterable {
    case task
    case question
    case report
    case fyi
}
