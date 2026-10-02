import Foundation
import Security

enum KeychainHelper {
    private static let service = AppIdentifiers.keychainService
    private static let legacyDefaultsPrefix = "debug_pwd_"

    /// Basisabfrage. Auf macOS wird der Data-Protection-Keychain genutzt (wie auf iOS).
    private static func baseQuery(account: String, dataProtection: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        #if os(macOS)
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        #endif
        return query
    }

    @discardableResult
    static func savePassword(_ password: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        var status = store(data, account: account, dataProtection: true)
        #if os(macOS)
        // Ohne Team-Signatur (z. B. ad-hoc Debug-Builds) steht der Data-Protection-Keychain nicht zur Verfügung.
        if status == errSecMissingEntitlement {
            status = store(data, account: account, dataProtection: false)
        }
        #endif

        if status != errSecSuccess {
            LogManager.shared.log("Keychain: Passwort speichern fehlgeschlagen (OSStatus \(status))", type: .error)
            return false
        }
        return true
    }

    private static func store(_ data: Data, account: String, dataProtection: Bool) -> OSStatus {
        let query = baseQuery(account: account, dataProtection: dataProtection)
        let update: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return updateStatus }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    static func readPassword(account: String) -> String? {
        if let password = read(account: account, dataProtection: true) {
            return password
        }
        #if os(macOS)
        // Einträge aus älteren Versionen (Legacy-Keychain) lesen und in den neuen Keychain übernehmen.
        if let legacy = read(account: account, dataProtection: false) {
            if savePassword(legacy, account: account) {
                SecItemDelete(legacyDeleteQuery(account: account) as CFDictionary)
            }
            return legacy
        }
        #endif
        return nil
    }

    private static func read(account: String, dataProtection: Bool) -> String? {
        var query = baseQuery(account: account, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    static func deletePassword(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        #if os(macOS)
        SecItemDelete(legacyDeleteQuery(account: account) as CFDictionary)
        #endif
        UserDefaults.standard.removeObject(forKey: legacyDefaultsPrefix + account)
    }

    #if os(macOS)
    private static func legacyDeleteQuery(account: String) -> [String: Any] {
        baseQuery(account: account, dataProtection: false)
    }
    #endif

    /// Einmalige Migration: Klartext-Passwörter aus früheren Debug-Builds (UserDefaults) in den Keychain verschieben
    /// und anschließend aus UserDefaults entfernen.
    static func migrateLegacyDefaultsPasswords() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(legacyDefaultsPrefix) {
            let account = String(key.dropFirst(legacyDefaultsPrefix.count))
            if let password = defaults.string(forKey: key), !account.isEmpty,
               read(account: account, dataProtection: true) == nil {
                guard savePassword(password, account: account) else { continue }
            }
            defaults.removeObject(forKey: key)
        }
    }
}
