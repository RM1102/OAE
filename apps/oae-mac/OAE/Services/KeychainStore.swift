import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case encodingFailed
    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let s): return "Keychain error (\(s))"
        case .encodingFailed: return "Could not encode string as UTF-8."
        }
    }
}

/// Thin generic-password Keychain wrapper. Keys are scoped by the app's bundle
/// identifier via `kSecAttrService`, and the per-provider account name uniquely
/// identifies which preset the key belongs to (e.g. `provider.groq`).
public enum KeychainStore {
    private static let service: String = {
        Bundle.main.bundleIdentifier ?? "computer.oae.OAE"
    }()

    public static func set(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func remove(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func accountName(forProvider id: String) -> String { "provider.\(id)" }
}
