import Foundation
import Security

/// Tiny Keychain wrapper for the two credentials the app holds: the Hugging Face
/// token and (optionally) the Osaurus API key. Never written to disk in the clear.
enum Keychain {
    private static let service = "hf.app"

    struct SaveError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain save failed (status \(status))."
        }
    }

    // Injectable operations keep regression tests away from the user's Keychain.
    struct Operations {
        var update: (CFDictionary, CFDictionary) -> OSStatus
        var add: (CFDictionary) -> OSStatus
        var delete: (CFDictionary) -> OSStatus

        static var system: Operations {
            Operations(update: { SecItemUpdate($0, $1) },
                       add: { SecItemAdd($0, nil) },
                       delete: { SecItemDelete($0) })
        }
    }

    static func set(_ value: String, for key: String,
                    operations: Operations = .system) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if value.isEmpty {
            let status = operations.delete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SaveError(status: status)
            }
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let status = operations.update(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = base.merging(attributes) { _, new in new }
            let added = operations.add(add as CFDictionary)
            guard added == errSecSuccess else { throw SaveError(status: added) }
        } else if status != errSecSuccess {
            throw SaveError(status: status)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        return s
    }
}
