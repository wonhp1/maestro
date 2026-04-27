import Foundation

/// 타입 시스템 수준에서 서로 다른 도메인 ID 를 구분하기 위한 phantom-typed 식별자.
///
/// `Identifier<EnvelopeTag>` 와 `Identifier<ThreadTag>` 는 내부적으로 같은 `String`
/// 을 감싸지만 **컴파일 타임에 섞어 쓸 수 없다**. 이는 "잘못된 ID 전달" 버그를
/// 근본적으로 차단한다.
///
/// ## 보안 경계
/// ID는 파일시스템 경로 컴포넌트 (예: `threads/<id>.jsonl`, `inbox/<agent>/`) 와
/// CLI 인자로 흘러들어간다. 따라서 `rawValue` 는 **엄격하게** 검증되어야 한다:
/// path traversal (`..`), null byte, shell meta, 제어 문자 모두 거부.
///
/// `init(rawValue:)` 는 내부/테스트용 — 사용자/디스크/CLI 외부 입력은 반드시
/// `validated(rawValue:)` 또는 `new()` 를 통과시킨다.
public struct Identifier<Tag>: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    /// 신뢰된 rawValue 로 직접 생성. 외부 입력에 사용 금지.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// UUID 기반 새 ID 생성. 항상 유효한 문자 집합을 만족.
    public static func new() -> Self {
        Self(rawValue: UUID().uuidString)
    }

    /// 외부 입력 (사용자 타이핑, 디스크 파일, CLI stdout) 검증.
    ///
    /// 허용: `[A-Za-z0-9._-]` 1-64자. 단, `.`/`-` 로 시작 금지, `..` 포함 금지.
    public static func validated(rawValue: String) throws -> Self {
        try Identifier.ensureValid(rawValue)
        return Self(rawValue: rawValue)
    }

    private static func ensureValid(_ value: String) throws {
        guard !value.isEmpty else {
            throw IdentifierError.emptyRawValue
        }
        guard value.count <= 64 else {
            throw IdentifierError.tooLong(length: value.count)
        }
        // 제어 문자 / 공백 / null 바이트 차단
        if value.rangeOfCharacter(from: .controlCharacters) != nil
            || value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            || value.contains("\u{0000}") {
            throw IdentifierError.containsForbiddenCharacter
        }
        // 경로 traversal 차단
        if value.contains("..") || value.contains("/") || value.contains("\\") {
            throw IdentifierError.pathTraversal
        }
        // 선두 `.` 또는 `-` 차단 (숨김 파일/플래그 혼동 방지)
        if let first = value.first, first == "." || first == "-" {
            throw IdentifierError.invalidLeadingCharacter
        }
        // 허용 문자 집합
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        if value.rangeOfCharacter(from: allowed.inverted) != nil {
            throw IdentifierError.disallowedCharacter
        }
    }

    public var description: String { rawValue }
}

/// Dictionary<Identifier, V> 가 JSON 에서 keyed object 로 인코딩되도록.
/// 미적용 시 Swift 기본 동작은 alternating `[k, v, k, v]` 배열 — 디스크/인스펙션
/// 가독성이 나쁘고 옛 형식 호환에도 불리.
extension Identifier: CodingKeyRepresentable {
    public var codingKey: CodingKey {
        StringCodingKey(stringValue: rawValue)
    }

    public init?<T: CodingKey>(codingKey: T) {
        let raw = codingKey.stringValue
        guard (try? Identifier.ensureValid(raw)) != nil else { return nil }
        self.init(rawValue: raw)
    }
}

private struct StringCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Identifier: Codable {
    /// 디스크/네트워크에서 역직렬화 시에도 반드시 검증.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        try Identifier.ensureValid(raw)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum IdentifierError: Error, Equatable {
    case emptyRawValue
    case tooLong(length: Int)
    case containsForbiddenCharacter
    case pathTraversal
    case invalidLeadingCharacter
    case disallowedCharacter
}

// MARK: - Phantom tag types + typealiases

public enum EnvelopeTag {}
public enum ThreadTag {}
public enum SessionTag {}
public enum AgentTag {}
public enum AdapterTag {}
public enum FolderTag {}

/// 메시지 봉투 식별자.
public typealias EnvelopeID = Identifier<EnvelopeTag>

/// 스레드(대화 묶음) 식별자. `Discussion` 의 ID 도 이것을 사용.
public typealias ThreadID = Identifier<ThreadTag>

/// 세션(에이전트 CLI 세션) 식별자. CLI 가 발급한 session_id 와 매핑.
///
/// - Note: CLI 가 UUID 가 아닌 hyphen 포함 문자열을 돌려줄 수 있으므로 검증 시
///   일반적인 `.-_0-9A-Za-z` 집합을 허용.
public typealias SessionID = Identifier<SessionTag>

/// 에이전트 식별자 (이름 기반). 예: `cpo`, `ai-news`.
public typealias AgentID = Identifier<AgentTag>

/// CLI 어댑터 식별자. 예: `claude`, `aider`, `gemini`.
///
/// Phase 2 에서 phantom-typed 로 승격 (기존 `String` 에서) — 보안 리뷰에서 지적된
/// "5번째 ID 공간" 으로 가장 자주 경계를 넘나듬.
public typealias AdapterID = Identifier<AdapterTag>

/// 사용자가 등록한 작업 폴더 식별자. UUID 기반.
///
/// `path` 와 분리된 stable identity — 사용자가 폴더를 옮겨도 (Phase 10 외 future)
/// 동일 폴더로 인식 가능. 디스크 (`folders.json`) 와 inbox 디렉토리 이름의 키.
public typealias FolderID = Identifier<FolderTag>
