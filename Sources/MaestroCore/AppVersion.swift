import Foundation

/// SemVer 비슷한 비교 가능 버전 (Major.Minor.Patch + optional pre-release).
///
/// Sparkle appcast 의 `<sparkle:version>` 값을 파싱 — `1.2.3` / `1.2.3-beta.1` 등 지원.
/// pre-release 가 있는 버전은 stable 버전보다 작음 (SemVer 2.0.0 §11).
public struct AppVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// "beta.1" / "rc.2" / nil. nil 이 우선순위 높음.
    public let preRelease: String?

    public init(major: Int, minor: Int, patch: Int, preRelease: String? = nil) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
        self.preRelease = preRelease?.isEmpty == true ? nil : preRelease
    }

    /// `"1.2.3"` 또는 `"1.2.3-beta.1"` 파싱. 실패 시 nil.
    public init?(string raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var working = trimmed
        if working.hasPrefix("v") || working.hasPrefix("V") {
            working = String(working.dropFirst())
        }
        let preReleaseSplit = working.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = preReleaseSplit[0]
        let pre = preReleaseSplit.count > 1 ? String(preReleaseSplit[1]) : nil
        let parts = core.split(separator: ".", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 3 else { return nil }
        let nums: [Int]
        let parsed = parts.map { Int($0) }
        guard parsed.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        nums = parsed.map { $0! }
        let major = nums[0]
        let minor = nums.count > 1 ? nums[1] : 0
        let patch = nums.count > 2 ? nums[2] : 0
        self.init(major: major, minor: minor, patch: patch, preRelease: pre)
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        if let preRelease { return "\(core)-\(preRelease)" }
        return core
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // 동일 core — pre-release 없는 쪽이 큼
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case (let l?, let r?): return l < r
        }
    }
}
