import Foundation

/// 프로젝트 공용 JSON 인코더/디코더 설정.
///
/// - 모든 영속 파일 (inbox envelope, threads JSONL, registry 등) 은 이 코덱을 사용해
///   디스크 포맷 일관성을 보장한다.
/// - 날짜는 **소수점 초 포함 ISO-8601** 사용 — `Date()` 의 마이크로초 정밀도를
///   roundtrip 에서 잃지 않도록 `.withFractionalSeconds` 활성.
/// - 필드는 `camelCase` 그대로 (변환 없음).
// ISO8601DateFormatter 는 Apple 문서상 read-only 사용 시 thread-safe (NSFormatter 공통).
// Swift 6 의 Sendable 검사는 이를 알지 못하므로 `nonisolated(unsafe)` 로 의도 표명.
nonisolated(unsafe) private let maestroISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

public extension JSONEncoder {
    /// Maestro 표준 인코더. 파일 직렬화 전용.
    static let maestro: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(maestroISO8601Formatter.string(from: date))
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
            if let date = maestroISO8601Formatter.date(from: string) {
                return date
            }
            // Fallback: 소수점 초 없는 ISO-8601 도 허용 (사용자 수동 편집 대비).
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: string) {
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
