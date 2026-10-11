import Foundation
import Security
import Supabase

/// Foreground-only account credentials, private to this device and app namespace.
/// Missing items are normal; every other Keychain failure is surfaced to callers.
struct SecureSessionStorage: AuthLocalStorage {
    let service: String

    init(service: String = "TeamStats.account.private.v1") {
        self.service = service
    }

    func store(key: String, value: Data) throws {
        let query = query(key: key)
        let attributes: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(updated)
        }
    }

    func retrieve(key: String) throws -> Data? {
        var query = query(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data else { throw AccountIssue.storage }
        return data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(query(key: key) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func query(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw AccountIssue.storage }
    }
}
