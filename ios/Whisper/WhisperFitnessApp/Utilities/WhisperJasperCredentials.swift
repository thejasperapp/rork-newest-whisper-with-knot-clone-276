import Foundation
import Security

/// Forgetting a device account removes only that owner's partner credentials.
enum WhisperJasperCredentials {
    static func forget(owner: String) {
        let owner = owner.lowercased()
        guard UUID(uuidString: owner) != nil else { return }
        for prefix in ["jasper_connect_meta_v2_", "jasper_coach_tokens_meta_v2_"] {
            UserDefaults.standard.removeObject(forKey: prefix + owner)
        }
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "jasper.connect",
            kSecAttrAccount as String: "jc_token_v2_" + owner,
        ] as CFDictionary)
        var matches: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "jasper.connect.coach",
                                  kSecReturnAttributes as String: true,
                                  kSecMatchLimit as String: kSecMatchLimitAll]
        if SecItemCopyMatching(query as CFDictionary, &matches) == errSecSuccess,
           let rows = matches as? [[String: Any]] {
            for row in rows {
                guard let account = row[kSecAttrAccount as String] as? String,
                      account.lowercased().hasPrefix(owner + ":") else { continue }
                SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: "jasper.connect.coach",
                               kSecAttrAccount as String: account] as CFDictionary)
            }
        }
    }
}
