import Foundation
import Security

/// Stores the Anthropic API key in the Keychain, shared with the share extension via the App Group.
enum KeychainStore {
    private static let service = "CardImport.AnthropicAPIKey"

    private static func baseQuery(shared: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "default"]
        if shared { q[kSecAttrAccessGroup as String] = AppGroup.identifier }
        return q
    }

    static func save(_ key: String) {
        let data = Data(key.utf8)
        for shared in [true, false] {
            SecItemDelete(baseQuery(shared: shared) as CFDictionary)
            var add = baseQuery(shared: shared)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    static func load() -> String? {
        for shared in [true, false] {
            var q = baseQuery(shared: shared)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let s = String(data: d, encoding: .utf8), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    static func delete() {
        for shared in [true, false] { SecItemDelete(baseQuery(shared: shared) as CFDictionary) }
    }
}
