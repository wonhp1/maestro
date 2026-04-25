import Foundation

/// 어댑터 스트리밍 응답의 **최소 단위**. CLI/LLM 출력을 카테고리별 청크로 정규화.
///
/// `AgentAdapter.streamMessage` 가 `AsyncThrowingStream<ResponseChunk, Error>`
/// 형태로 발행. UI 가 점진적으로 렌더링하기 위한 표준 표현.
///
/// `content` 는 `kind` 에 따라 의미가 다르다:
/// - `.text`: 사용자에게 보여줄 raw 텍스트 조각
/// - `.thinking`: 모델 내부 사고 (Claude extended thinking 등). UI 는 보통 collapsed 표시.
/// - `.toolUse`: JSON 인코딩된 툴 호출 페이로드 (어댑터별 스키마)
/// - `.toolResult`: JSON 인코딩된 툴 실행 결과
/// - `.error`: stream 을 종료하지 않는 mid-stream 경고/회복 가능 에러
/// - `.completion`: 턴 종료 마커. `content` 는 보통 빈 문자열, 필요시 종료 사유
///
/// - Note: enum case 추가는 source-breaking 이라 Phase 4 에서 미리 확장 (리뷰 must-fix).
public struct ResponseChunk: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case text
        case thinking
        case toolUse
        case toolResult
        case error
        case completion
    }

    public let kind: Kind
    public let content: String
    public let timestamp: Date

    public init(kind: Kind, content: String, timestamp: Date = Date()) {
        self.kind = kind
        self.content = content
        self.timestamp = timestamp
    }
}

public extension ResponseChunk {
    /// 텍스트 청크 편의 생성자.
    static func text(_ text: String, at time: Date = Date()) -> ResponseChunk {
        ResponseChunk(kind: .text, content: text, timestamp: time)
    }

    /// 턴 종료 마커 편의 생성자.
    static func completion(reason: String = "", at time: Date = Date()) -> ResponseChunk {
        ResponseChunk(kind: .completion, content: reason, timestamp: time)
    }
}
