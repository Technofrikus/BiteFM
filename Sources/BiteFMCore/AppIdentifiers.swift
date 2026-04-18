import Foundation

/// Zentrale Kennungen für Keychain und Logging. Bei Wechsel des Bundle-ID-Präfixes (`project.yml` → `bundleIdPrefix`)
/// hier denselben Vendor-String wie bisher pflegen, sonst sind gespeicherte Keychain-Einträge unter altem Service-Namen nicht mehr lesbar.
enum AppIdentifiers {
    static let keychainService = "com.Moinboards.BiteFM"
    static let logSubsystem = "com.Moinboards.BiteFM"
}
