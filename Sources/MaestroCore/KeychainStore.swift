import Foundation
import Security

/// macOS Keychain 기반 비밀 저장소.
///
/// API 키, OAuth 토큰 등 민감한 문자열 전용. 평문 파일 저장 절대 금지 — 모든
/// 시크릿은 이 타입을 통해 `kSecClassGenericPassword` 항목으로 저장.
///
/// ## 접근성
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — 기기 잠금 해제 시에만 접근,
/// iCloud 동기화 안 함 (로컬 완결 원칙).
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
        let accountQuery = baseQuery(account: key)

        // 먼저 업데이트 시도 (동일 account 가 이미 있으면 값만 교체)
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            accountQuery as CFDictionary,
            updateAttrs as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw PersistenceError.keychainFailed(status: updateStatus)
        }

        // 없으면 새로 추가. `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 로 iCloud 비동기화.
        //
        // Note: `kSecUseDataProtectionKeychain` 은 Xcode 앱 번들에서만 기본 활성.
        // CLI/SPM executable 은 entitlement 없이 전통 keychain 만 사용 가능 (Phase 21
        // Xcode 프로젝트 래핑 시 data-protection keychain 으로 업그레이드 가능).
        var addQuery = accountQuery
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
        ]
        // 안전장치: 무한 루프 방지 상한 (실제 보관 항목 수 < 1000 이 정상 시나리오)
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
        ]
    }
}
