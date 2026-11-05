import Foundation
import Security

/// Stores small secrets (like the claude.ai session key) in the macOS Keychain
/// as "generic password" items owned by this app.
enum Keychain {
    private static let service = "com.peekmenubar.app"

    enum Account: String {
        case claudeSessionKey = "claude.ai session key"
    }

    static func read(_ account: Account) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, for account: Account) -> Bool {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update)
        if status == errSecSuccess { return true }

        var add = baseQuery(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: Account) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }
}
