import Foundation

/// 에이전트 응답에서 `<REPLY_TO=...>` / `<RELAY_TO=...>` 태그를 추출.
///
/// ## 태그 포맷
/// ```
/// <REPLY_TO=envelope-id>
/// 응답 본문 (markdown)
/// </REPLY_TO>
///
/// <RELAY_TO=agent-name>
/// 다른 에이전트에게 전달할 메시지
/// </RELAY_TO>
/// ```
///
/// - `REPLY_TO` 는 명시적인 inReplyTo 지정 — DispatchService 가 envelope.inReplyTo
///   값으로 사용. 없으면 호출 컨텍스트에서 추론.
/// - `RELAY_TO` 는 릴레이 — DispatchService 가 별도 envelope 을 spawn 하여
///   해당 agent 로 dispatch.
///
/// ## 보안
/// - 태그 attribute 값은 **Identifier.validated** 통과만 사용 — path traversal /
///   shell meta / control char 차단.
/// - 태그 안 본문은 그대로 전달 (markdown sanitize 는 별도 layer 책임).
/// - 잘못된 태그 (닫는 태그 누락, attribute 위반) 은 silently skip + invalidTagCount
///   증가.
public struct ReplyParser: Sendable {
    /// 입력 본문의 최대 byte 길이 — 초과 시 잘라냄 (must-fix MED-4: regex DoS 방어).
    public static let defaultMaxInputBytes: Int = 256 * 1024
    /// reply 1건 당 허용 최대 RELAY_TO 개수 — wide fan-out 차단 (must-fix HIGH-2).
    public static let defaultMaxRelaysPerReply: Int = 8

    public let maxInputBytes: Int
    public let maxRelaysPerReply: Int

    public init(
        maxInputBytes: Int = ReplyParser.defaultMaxInputBytes,
        maxRelaysPerReply: Int = ReplyParser.defaultMaxRelaysPerReply
    ) {
        self.maxInputBytes = max(1, maxInputBytes)
        self.maxRelaysPerReply = max(1, maxRelaysPerReply)
    }

    /// 사용자/외부 본문에서 dispatch 태그를 strip — 재귀 relay 인젝션 방어
    /// (must-fix HIGH-3). DispatchService 가 user input 또는 relay 본문을 envelope.body
    /// 로 보내기 전에 반드시 호출.
    public static func stripDispatchTags(_ input: String) -> String {
        var output = input
        let patterns = [
            "<REPLY_TO=[^>]+>.*?</REPLY_TO>",
            "<RELAY_TO=[^>]+>.*?</RELAY_TO>",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.dotMatchesLineSeparators]
            ) else { continue }
            let nsString = output as NSString
            let range = NSRange(location: 0, length: nsString.length)
            output = regex.stringByReplacingMatches(
                in: output, options: [], range: range, withTemplate: ""
            )
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func parse(_ input: String) -> ParsedReplies {
        // input cap — adversarial 거대 입력 방어
        let truncated: String
        if input.utf8.count > maxInputBytes {
            let endIdx = input.utf8.index(input.utf8.startIndex, offsetBy: maxInputBytes)
            truncated = String(decoding: input.utf8[..<endIdx], as: UTF8.self)
        } else {
            truncated = input
        }
        return parseInternal(truncated)
    }

    private func parseInternal(_ input: String) -> ParsedReplies {
        var stripped = input
        var invalidCount = 0
        let replies = extractReplies(from: &stripped, invalidCount: &invalidCount)
        let relays = extractRelays(from: &stripped, invalidCount: &invalidCount)
        return ParsedReplies(
            remainingBody: stripped.trimmingCharacters(in: .whitespacesAndNewlines),
            replies: replies,
            relays: relays,
            invalidTagCount: invalidCount
        )
    }

    private func extractReplies(
        from stripped: inout String, invalidCount: inout Int
    ) -> [InlineReply] {
        guard let regex = try? NSRegularExpression(
            pattern: "<REPLY_TO=([^>]+)>(.*?)</REPLY_TO>",
            options: [.dotMatchesLineSeparators]
        ) else { return [] }
        var replies: [InlineReply] = []
        let nsString = stripped as NSString
        let matches = regex.matches(in: stripped, range: NSRange(location: 0, length: nsString.length))
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let attr = nsString.substring(with: match.range(at: 1))
            let body = nsString.substring(with: match.range(at: 2))
            if let validated = try? EnvelopeID.validated(rawValue: attr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                replies.append(InlineReply(
                    inReplyTo: validated,
                    body: body.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                stripped = (stripped as NSString).replacingCharacters(in: match.range, with: "")
            } else {
                invalidCount += 1
            }
        }
        replies.reverse()
        return replies
    }

    private func extractRelays(
        from stripped: inout String, invalidCount: inout Int
    ) -> [InlineRelay] {
        guard let regex = try? NSRegularExpression(
            pattern: "<RELAY_TO=([^>]+)>(.*?)</RELAY_TO>",
            options: [.dotMatchesLineSeparators]
        ) else { return [] }
        var relays: [InlineRelay] = []
        let nsString = stripped as NSString
        let matches = regex.matches(in: stripped, range: NSRange(location: 0, length: nsString.length))
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            if relays.count >= maxRelaysPerReply {
                // wide fan-out cap 초과 — strip + invalidCount 증가 (HIGH-2)
                invalidCount += 1
                stripped = (stripped as NSString).replacingCharacters(in: match.range, with: "")
                continue
            }
            let attr = nsString.substring(with: match.range(at: 1))
            let body = nsString.substring(with: match.range(at: 2))
            if let validated = try? AgentID.validated(rawValue: attr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                relays.append(InlineRelay(
                    target: validated,
                    body: body.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                stripped = (stripped as NSString).replacingCharacters(in: match.range, with: "")
            } else {
                invalidCount += 1
            }
        }
        relays.reverse()
        return relays
    }
}

public struct ParsedReplies: Sendable, Equatable {
    /// 태그를 모두 제거한 후 남은 본문 (free-form 응답).
    public let remainingBody: String
    /// 명시적 inReplyTo 가 있는 응답들.
    public let replies: [InlineReply]
    /// 릴레이 대상.
    public let relays: [InlineRelay]
    /// validated 통과 못한 태그 수.
    public let invalidTagCount: Int

    public init(
        remainingBody: String,
        replies: [InlineReply],
        relays: [InlineRelay],
        invalidTagCount: Int = 0
    ) {
        self.remainingBody = remainingBody
        self.replies = replies
        self.relays = relays
        self.invalidTagCount = invalidTagCount
    }
}

public struct InlineReply: Sendable, Equatable {
    public let inReplyTo: EnvelopeID
    public let body: String

    public init(inReplyTo: EnvelopeID, body: String) {
        self.inReplyTo = inReplyTo
        self.body = body
    }
}

public struct InlineRelay: Sendable, Equatable {
    public let target: AgentID
    public let body: String

    public init(target: AgentID, body: String) {
        self.target = target
        self.body = body
    }
}
