import Foundation

/// 타입 시스템 수준에서 서로 다른 도메인 ID 를 구분하기 위한 phantom-typed 식별자.
///
/// `Identifier<EnvelopeTag>` 와 `Identifier<ThreadTag>` 는 내부적으로 같은 `String`
/// 을 감싸지만 **컴파일 타임에 섞어 쓸 수 없다**. 이는 "잘못된 ID 전달" 버그를
/// 근본적으로 차단한다.
public struct Identifier<Tag>: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// UUID 기반 새 ID 생성. CLI 세션 ID 와 호환되는 형식.
    public static func new() -> Self {
        Self(rawValue: UUID().uuidString)
    }

    /// 공백이 아닌 rawValue 만 허용하는 검증된 생성자.
    public static func validated(rawValue: String) throws -> Self {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IdentifierError.emptyRawValue
        }
        return Self(rawValue: trimmed)
    }

    public var description: String { rawValue }
}

extension Identifier: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum IdentifierError: Error, Equatable {
    case emptyRawValue
}

// MARK: - Phantom tag types + typealiases

public enum EnvelopeTag {}
public enum ThreadTag {}
public enum SessionTag {}
public enum AgentTag {}

/// 메시지 봉투 식별자.
public typealias EnvelopeID = Identifier<EnvelopeTag>

/// 스레드(대화 묶음) 식별자. `Discussion` 의 ID 도 이것을 사용.
public typealias ThreadID = Identifier<ThreadTag>

/// 세션(에이전트 CLI 세션) 식별자. CLI 가 발급한 session_id 와 매핑.
public typealias SessionID = Identifier<SessionTag>

/// 에이전트 식별자 (이름 기반). 예: `"cpo"`, `"ai-news"`.
public typealias AgentID = Identifier<AgentTag>
