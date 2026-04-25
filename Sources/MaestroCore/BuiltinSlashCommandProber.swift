import Foundation

/// `claude -p "/help"` 출력에서 내장 슬래시 명령을 추출하고 디스크에 24h TTL 캐시.
///
/// ## 캐시 정책
/// - **TTL**: 기본 24h. 만료 시 다음 `discover()` 가 재프로빙.
/// - **바이너리 무효화**: 캐시 안의 `claudeBinaryPath` 가 현재 실행파일 경로와
///   다르면 무효화 (Claude 업그레이드 / 재설치).
/// - **mtime 무효화**: 캐시 안의 `binaryMTime` 이 현재 mtime 과 다르면 무효화
///   (같은 경로지만 새 빌드 — Quality Gate "버전 업그레이드 시 재프로빙").
///
/// ## 동시성
/// actor — 동시에 여러 호출 와도 한 번만 프로빙.
///
/// ## 보안
/// - 외부 프로세스 출력은 신뢰하지 않음. 명령 이름은 ASCII 영숫자/`_`/`-` 만 통과.
/// - 사이즈 cap: stdout 64 KiB 까지만 파싱 시도 (그 이상 비정상).
public actor BuiltinSlashCommandProber: SlashCommandSource {
    public struct Cache: Codable, Sendable, Equatable {
        public let probedAt: Date
        public let claudeBinaryPath: String
        public let binaryMTime: Date?
        public let commands: [SlashCommand]

        public init(
            probedAt: Date,
            claudeBinaryPath: String,
            binaryMTime: Date?,
            commands: [SlashCommand]
        ) {
            self.probedAt = probedAt
            self.claudeBinaryPath = claudeBinaryPath
            self.binaryMTime = binaryMTime
            self.commands = commands
        }
    }

    public static let defaultTTL: TimeInterval = 24 * 60 * 60
    public static let maxStdoutBytes: Int = 64 * 1024

    public let claudeExecutable: URL?
    public let cacheFile: URL
    public let ttl: TimeInterval
    public let executor: ProcessExecuting
    public let now: @Sendable () -> Date

    private var memoCache: Cache?

    public init(
        claudeExecutable: URL?,
        cacheFile: URL,
        ttl: TimeInterval = BuiltinSlashCommandProber.defaultTTL,
        executor: ProcessExecuting,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.claudeExecutable = claudeExecutable
        self.cacheFile = cacheFile
        self.ttl = max(0, ttl)
        self.executor = executor
        self.now = now
    }

    public func discover() async -> [DiscoveredSlashCommand] {
        let commands = await commandsRespectingCache()
        return commands.map {
            DiscoveredSlashCommand(command: $0, source: .builtin, filePath: nil)
        }
    }

    public func invalidate() {
        memoCache = nil
        try? FileManager.default.removeItem(at: cacheFile)
    }

    /// 테스트 / 디버그 — 현재 캐시 상태 raw 반환. **freshness 검증 없음** —
    /// 실제 commands 가 필요하면 `discover()` 호출.
    public func currentCache() -> Cache? {
        memoCache ?? loadDiskCache()
    }

    private func commandsRespectingCache() async -> [SlashCommand] {
        if let cache = loadValidCache() {
            memoCache = cache
            return cache.commands
        }
        guard let exe = claudeExecutable else { return [] }
        let probed = await probe(executable: exe)
        let mtime = Self.binaryMTime(at: exe)
        let cache = Cache(
            probedAt: now(),
            claudeBinaryPath: exe.path,
            binaryMTime: mtime,
            commands: probed
        )
        memoCache = cache
        try? saveCache(cache)
        return probed
    }

    private func loadValidCache() -> Cache? {
        let candidate = memoCache ?? loadDiskCache()
        guard let cache = candidate else { return nil }
        guard isStillFresh(cache) else { return nil }
        if let exe = claudeExecutable {
            if cache.claudeBinaryPath != exe.path { return nil }
            let currentMTime = Self.binaryMTime(at: exe)
            if cache.binaryMTime != currentMTime { return nil }
        }
        return cache
    }

    private func loadDiskCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? JSONDecoder.maestro.decode(Cache.self, from: data)
    }

    private func isStillFresh(_ cache: Cache) -> Bool {
        return now().timeIntervalSince(cache.probedAt) < ttl
    }

    private func saveCache(_ cache: Cache) throws {
        let data = try JSONEncoder.maestro.encode(cache)
        try FileManager.default.createDirectory(
            at: cacheFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: cacheFile, options: .atomic)
    }

    private func probe(executable: URL) async -> [SlashCommand] {
        do {
            let result = try await executor.run(
                executable: executable,
                arguments: ["-p", "/help"]
            )
            guard result.exitCode == 0 else { return [] }
            return Self.parseHelpOutput(result.stdout)
        } catch {
            return []
        }
    }

    /// `claude -p "/help"` stdout 을 파싱.
    ///
    /// 우리는 두 가지 흔한 라인 형식을 인식:
    /// - `/<name> - <description>`
    /// - `/<name>   <description>`
    /// 그 외 라인은 무시 (배너/구분선/설명문).
    public static func parseHelpOutput(_ output: String) -> [SlashCommand] {
        let truncated: Substring
        if output.utf8.count > maxStdoutBytes {
            let endIdx = output.utf8.index(
                output.utf8.startIndex, offsetBy: maxStdoutBytes
            )
            truncated = Substring(String(decoding: output.utf8[..<endIdx], as: UTF8.self))
        } else {
            truncated = Substring(output)
        }

        var seen: Set<String> = []
        var result: [SlashCommand] = []
        for raw in truncated.split(whereSeparator: \.isNewline) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("/") else { continue }
            let body = trimmed.dropFirst()
            // 형식 1: "/name - description"
            if let dash = body.range(of: " - ") {
                let name = String(body[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
                let desc = String(body[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
                appendIfValid(name: name, description: desc, into: &result, seen: &seen)
                continue
            }
            // 형식 2: "/name <whitespace>+ description"
            if let ws = body.firstIndex(where: { $0.isWhitespace }) {
                let name = String(body[..<ws]).trimmingCharacters(in: .whitespaces)
                let desc = String(body[ws...]).trimmingCharacters(in: .whitespaces)
                appendIfValid(name: name, description: desc, into: &result, seen: &seen)
                continue
            }
            // 단독 토큰 라인 (`/foo` 만)
            appendIfValid(name: String(body), description: "", into: &result, seen: &seen)
        }
        return result
    }

    private static func appendIfValid(
        name: String,
        description: String,
        into result: inout [SlashCommand],
        seen: inout Set<String>
    ) {
        guard isValidName(name) else { return }
        guard seen.insert(name).inserted else { return }
        result.append(SlashCommand(
            name: name,
            description: description,
            category: SlashCommandSourceKind.builtin.rawValue
        ))
    }

    private static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func binaryMTime(at url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}
