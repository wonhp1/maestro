import Foundation

/// v0.5.0 — 토론 메모 디스크 저장소. actor 직렬화로 동시 read/write 안전.
///
/// 위치: `<root>/discussion-memos/<id>.md`
///
/// ## 책임
/// - YAML-lite frontmatter + body 직렬화/역직렬화 (외부 의존 없이 plain Foundation).
/// - in-memory cache — 매 sendMessage 마다 파일시스템 hit 회피.
/// - filter by AgentID — ClaudeAdapter provider 가 호출 시 활성 메모만 반환.
public actor AgentMemoStore {
    private let directory: URL
    private let fileManager: FileManager
    private var cache: [ThreadID: DiscussionMemo] = [:]
    private var loaded: Bool = false

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// 최초 1회 디스크에서 모든 메모 로드 — 이후엔 cache 만 사용. 파일이 외부에서
    /// 변경될 수 있는 다중 인스턴스 환경은 가정하지 않음 (single-user local app).
    public func loadAll() throws {
        try ensureDirectory()
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        cache = [:]
        for url in urls where url.pathExtension == "md" {
            do {
                let data = try Data(contentsOf: url)
                let text = String(decoding: data, as: UTF8.self)
                let memo = try DiscussionMemoCoder.decode(text: text)
                cache[memo.id] = memo
            } catch {
                // 손상 파일 1개가 다른 메모 로드를 막지 않게 silently skip.
                continue
            }
        }
        loaded = true
    }

    public func all() -> [DiscussionMemo] {
        Array(cache.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func memo(id: ThreadID) -> DiscussionMemo? { cache[id] }

    /// 특정 agent 에 활성으로 공유된 메모만 반환 (시간 역순). 빈 배열 가능.
    public func activeMemos(for agent: AgentID) -> [DiscussionMemo] {
        cache.values
            .filter { $0.active && $0.sharedWith.contains(agent) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 메모 저장 + cache 갱신. atomic write 로 partial 저장 방지.
    public func save(_ memo: DiscussionMemo) throws {
        try ensureDirectory()
        let url = directory.appending(
            path: "\(memo.id.rawValue).md", directoryHint: .notDirectory
        )
        let text = DiscussionMemoCoder.encode(memo)
        try Data(text.utf8).write(to: url, options: [.atomic])
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
        cache[memo.id] = memo
    }

    public func delete(id: ThreadID) throws {
        let url = directory.appending(
            path: "\(id.rawValue).md", directoryHint: .notDirectory
        )
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        cache[id] = nil
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: directory.path
            )
        }
    }
}

// MARK: - Frontmatter encoder/decoder (YAML-lite, no external dep)

/// 단순 frontmatter encoder/decoder — 외부 YAML 라이브러리 없이 Maestro 가
/// 쓰는 필드만 다룸. 사람 친화 + 손쉬운 grep 위해 plain text.
enum DiscussionMemoCoder {
    /// ISO8601DateFormatter 는 Sendable 이 아니지만 모든 메서드가 thread-safe (Apple
    /// 문서 + ICU 내부) — Swift 6 strict 검사를 위해 호출 시점에 fresh 생성.
    private static func makeFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    static func encode(_ memo: DiscussionMemo) -> String {
        let sharedList = memo.sharedWith
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ", ")
        var lines: [String] = [
            "---",
            "discussionId: \(memo.id.rawValue)",
            "title: \(escapeForYAML(memo.title))",
            "sharedWith: [\(sharedList)]",
            "updatedAt: \(makeFormatter().string(from: memo.updatedAt))",
            "active: \(memo.active ? "true" : "false")",
            "---",
            "",
        ]
        lines.append(memo.body)
        return lines.joined(separator: "\n")
    }

    static func decode(text: String) throws -> DiscussionMemo {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2, lines[0].trimmingCharacters(in: .whitespaces) == "---" else {
            throw DiscussionMemoError.malformedFrontmatter
        }
        var meta: [String: String] = [:]
        var bodyStart = -1
        for i in 1..<lines.count {
            let raw = String(lines[i])
            if raw.trimmingCharacters(in: .whitespaces) == "---" {
                bodyStart = i + 1
                break
            }
            if let colon = raw.firstIndex(of: ":") {
                let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(raw[raw.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                meta[key] = value
            }
        }
        guard bodyStart >= 0 else {
            throw DiscussionMemoError.malformedFrontmatter
        }
        guard let idRaw = meta["discussionId"] else {
            throw DiscussionMemoError.missingRequiredField("discussionId")
        }
        let id = try ThreadID.validated(rawValue: idRaw)
        let title = unescapeFromYAML(meta["title"] ?? "")
        let sharedWith = parseAgentList(meta["sharedWith"] ?? "[]")
        let updated = (meta["updatedAt"].flatMap { makeFormatter().date(from: $0) }) ?? Date()
        let active = (meta["active"] ?? "true") == "true"
        var bodyLines: [Substring] = []
        if bodyStart < lines.count {
            // 본문 첫 빈 줄은 frontmatter 와의 separator — skip
            var idx = bodyStart
            if idx < lines.count, lines[idx].isEmpty { idx += 1 }
            bodyLines = Array(lines[idx...])
        }
        let body = bodyLines.joined(separator: "\n")
        return DiscussionMemo(
            id: id,
            title: title,
            body: String(body),
            sharedWith: sharedWith,
            updatedAt: updated,
            active: active
        )
    }

    private static func parseAgentList(_ raw: String) -> [AgentID] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return [] }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
            .compactMap { try? AgentID.validated(rawValue: $0) }
    }

    private static func escapeForYAML(_ value: String) -> String {
        // YAML scalar — newline / colon 가 끼면 quote. 항상 quote 가 안전.
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func unescapeFromYAML(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
