import Foundation
import Security

/// macOS Keychain 기반 비밀 저장소.
///
/// API 키, OAuth 토큰 등 민감한 문자열 전용. 평문 파일 저장 절대 금지 — 모든
/// 시크릿은 이 타입을 통해 `kSecClassGenericPassword` 항목으로 저장.
///
/// ## 접근성 및 동기화
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — 기기 잠금 해제 시에만 접근.
/// - `kSecAttrSynchronizable = false` — iCloud Keychain 동기화 명시적 비활성
///   (로컬 완결 원칙).
/// - 두 속성 모두 update 경로에서도 보존 — legacy 루즈 항목 재기록 시 strict 복구.
///
/// ## 동시성
/// `struct` + 내부 상태 없음 — 자유롭게 여러 스레드에서 사용 가능.
public struct KeychainStore: Sendable {
    /// Keychain `kSecAttrService` 값. 번들 ID 기반이 기본.
    public let service: String

    public init(service: String = MaestroConfig.bundleIdentifier) {
        self.service = service
    }

    // MARK: CRUD

    public func set(_ key: String, value: String) throws {
        let data = Data(value.utf8)

        // 먼저 기존 항목 삭제 후 다시 추가 — 이전 루즈 설정 (accessibility / sync) 이
        // 잔존하지 않도록. update-only 는 legacy 속성을 덮어쓰지 못함.
        let baseDeleteQuery = baseQuery(account: key)
        let deleteStatus = SecItemDelete(baseDeleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw PersistenceError.keychainFailed(status: deleteStatus)
        }

        var addQuery = baseDeleteQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PersistenceError.keychainFailed(status: addStatus)
        }
    }

    public func get(_ key: String) throws -> String? {
        var query = baseQuery(account: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw PersistenceError.keychainFailed(status: status)
        }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    public func delete(_ key: String) throws {
        let query = baseQuery(account: key)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw PersistenceError.keychainFailed(status: status)
    }

    /// 이 service 아래 모든 항목 제거. 테스트 cleanup / 계정 로그아웃용.
    ///
    /// - Note: macOS legacy keychain 은 `SecItemDelete` 가 단일 항목 삭제로 동작하므로
    ///   `errSecItemNotFound` 나올 때까지 반복.
    public func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
        // 상한: 루프가 무한 반복하는 상황은 버그 — 보관 항목 수의 상한으로 방어.
        for _ in 0..<10_000 {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecItemNotFound { return }
            if status != errSecSuccess {
                throw PersistenceError.keychainFailed(status: status)
            }
        }
    }

    // MARK: Helpers

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // iCloud 동기화 명시적 차단 — 쿼리/삭제에서 동기화 항목과 섞이지 않게.
            kSecAttrSynchronizable as String: false,
        ]
    }
}
