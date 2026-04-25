import Foundation

/// 어댑터별 API 키 저장 — 100% Keychain.
///
/// ## 책임
/// - **네임스페이스**: `adapter:<id>:apiKey` 형식 단일 키. 다른 시크릿(OAuth refresh 등)은
///   별도 facade.
/// - **id 검증**: ASCII 영숫자 + `_-` 만 허용 (1~64자). path/query 등 인젝션 차단.
/// - **빈 값 = 삭제**: setKey(adapter, "") → delete. nil 반환은 미설정.
///
/// ## 보안
/// - 값은 절대 메모리 외부로 직렬화 X. UI 가 일시적으로 표시할 땐 즉시 해제.
/// - `KeychainStore` 가 0600-equivalent 접근성 (`WhenUnlockedThisDeviceOnly`) 강제.
/// - **iCloud Keychain 동기화 비활성** (KeychainStore 가 명시).
public struct APIKeyStorage: Sendable {
    public let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func key(for adapterID: String) throws -> String? {
        let lookup = try Self.makeKey(adapterID: adapterID)
        return try keychain.get(lookup)
    }

    public func setKey(for adapterID: String, value: String) throws {
        let lookup = try Self.makeKey(adapterID: adapterID)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.delete(lookup)
            return
        }
        try keychain.set(lookup, value: trimmed)
    }

    public func deleteKey(for adapterID: String) throws {
        let lookup = try Self.makeKey(adapterID: adapterID)
        try keychain.delete(lookup)
    }

    /// `adapter:<id>:apiKey` — id 검증 후 반환.
    static func makeKey(adapterID: String) throws -> String {
        guard isValidID(adapterID) else {
            throw APIKeyStorageError.invalidAdapterID(adapterID)
        }
        return "adapter:\(adapterID):apiKey"
    }

    static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

public enum APIKeyStorageError: Error, Equatable, Sendable {
    case invalidAdapterID(String)
}
