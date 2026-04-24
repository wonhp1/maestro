import Foundation

/// 프로젝트 공용 JSON 인코더/디코더 설정.
///
/// - 모든 영속 파일 (inbox envelope, threads JSONL, registry 등) 은 이 코덱을 사용해
///   디스크 포맷 일관성을 보장한다.
/// - 날짜는 **소수점 초 포함 ISO-8601** 사용 — `Date()` 의 밀리초 정밀도 유지.
/// - 필드는 `camelCase` 그대로 (변환 없음).
/// - `sortedKeys` 출력 — Git diff 안정성 + 테스트 용이성.
///
/// ## 동시성
/// Swift 6 macOS 12+ 의 `Date.ISO8601FormatStyle` 은 값 타입 + `Sendable` 이라
/// 공유 mutable state 가 없다. 이전 버전의 `nonisolated(unsafe)`
/// `ISO8601DateFormatter` 대비 안전하고 깔끔.
public extension JSONEncoder {
    /// Maestro 표준 인코더. 파일 직렬화 전용.
    static let maestro: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(
                date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            )
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

public extension JSONDecoder {
    /// Maestro 표준 디코더. 파일 역직렬화 전용.
    static let maestro: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            // Primary: 소수점 초 포함
            if let date = try? Date(
                string,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            ) {
                return date
            }
            // Fallback: 소수점 초 없는 ISO-8601 (사용자 수동 편집 대비)
            if let date = try? Date(string, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "ISO-8601 날짜 파싱 실패: \(string)"
            )
        }
        return decoder
    }()
}
