import Foundation

/// 사용자가 등록한 작업 폴더 한 건의 메타데이터.
///
/// ## 의미론
/// 한 폴더 = 한 에이전트 세션의 cwd. 사용자가 "+ 폴더 추가" 로 NSOpenPanel 을 통해
/// 디렉토리를 선택하면 `FolderRegistration` 한 건이 생성되고 `folders.json` 에 영속됨.
///
/// ## 보안 / 검증
/// - `path` 는 **반드시 절대 경로** (file://). 디스크에서 로드한 값도 검증.
/// - `displayName` 은 1-128자, 제어 문자 금지 (다른 로컬 사용자가 표시 위협 못 하도록).
/// - `adapterId` 는 등록된 어댑터 중 하나여야 함 — 검증 책임은 `FolderRegistry` (소비
///   시점 검증, 모델 자체는 어댑터 존재 여부 모름).
/// - 신뢰 경계: 사용자가 직접 선택한 폴더만 등록 가능 (NSOpenPanel). 외부 입력 (deep
///   link 등) 으로 등록 금지 — Phase 10 범위 외.
public struct FolderRegistration: Codable, Hashable, Sendable, Identifiable {
    public let id: FolderID
    public var displayName: String
    public var path: URL
    public var adapterId: AdapterID
    public let createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: FolderID = .new(),
        displayName: String,
        path: URL,
        adapterId: AdapterID,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.adapterId = adapterId
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// 표시 이름 검증 — 등록/업데이트 진입점.
    ///
    /// 차단:
    /// - 빈 문자열 / 128자 초과
    /// - `.controlCharacters` (\u{0000}-\u{001F}, \u{007F} 등)
    /// - **bidi / zero-width / BOM** — Trojan Source 스타일 spoofing 차단
    ///   (예: `dispatch\u{202E}sohw.fdp` 가 알림창에서 reverse 렌더되어 다른
    ///   에이전트로 보이게 함). 시큐리티 리뷰 must-fix.
    public static func validateDisplayName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FolderRegistrationError.emptyDisplayName
        }
        guard trimmed.count <= 128 else {
            throw FolderRegistrationError.displayNameTooLong(length: trimmed.count)
        }
        if trimmed.rangeOfCharacter(from: .controlCharacters) != nil {
            throw FolderRegistrationError.displayNameContainsControlCharacter
        }
        if trimmed.rangeOfCharacter(from: Self.spoofingCharacters) != nil {
            throw FolderRegistrationError.displayNameContainsControlCharacter
        }
    }

    /// 폴더 경로 검증 — 절대 경로 + file:// + 디렉토리 존재 + **심볼릭 링크 해소 검증**.
    ///
    /// 보안 핵심: `validatePath` 가 통과한 URL 의 `resolvingSymlinksInPath()` 경로가
    /// 입력과 다르면 throws — 사용자가 `~/Projects/notes -> /etc` 같은 함정 심볼릭
    /// 링크를 선택해도 Aider 의 `--yes-always` (Phase 9) 와 결합한 RCE 차단.
    /// 심볼릭 링크가 정상적인 사용 케이스 (예: `~/code -> /Volumes/...`) 인 경우는
    /// `resolved == standardized` 가 false 이지만 실제 디렉토리이므로 별도 케이스로
    /// `pathIsSymlink` 반환 — 호출자가 사용자에게 confirm 받고 resolved path 로 재시도.
    ///
    /// - Returns: 사용해야 할 정규화 + 심볼릭 링크 해소된 URL. 호출자는 이 값을
    ///   `FolderRegistration.path` 에 저장해야 함 (NOT 입력 URL).
    @discardableResult
    public static func validatePath(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard url.isFileURL else {
            throw FolderRegistrationError.pathMustBeFileURL
        }
        let standardized = url.standardizedFileURL
        guard standardized.path.hasPrefix("/") else {
            throw FolderRegistrationError.pathMustBeAbsolute
        }
        let resolvedPath = (standardized.path as NSString).resolvingSymlinksInPath
        let resolved = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw FolderRegistrationError.pathIsNotADirectory(path: standardized.path)
        }
        return resolved
    }

    /// Trojan Source 방어용 spoofing 문자 집합.
    /// - Bidi controls: U+202A-U+202E, U+2066-U+2069
    /// - Zero-width: U+200B-U+200D, U+FEFF
    private static let spoofingCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}")
        set.insert(charactersIn: "\u{2066}\u{2067}\u{2068}\u{2069}")
        set.insert(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}")
        return set
    }()
}

public enum FolderRegistrationError: Error, Equatable, Sendable {
    case emptyDisplayName
    case displayNameTooLong(length: Int)
    case displayNameContainsControlCharacter
    case pathMustBeFileURL
    case pathMustBeAbsolute
    case pathIsNotADirectory(path: String)
}
