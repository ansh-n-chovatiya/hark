import Foundation
import HarkCore
import Security

/// One generic password in the user's login Keychain. The app that made it can read it again without
/// a prompt, because every build is signed with the same identity.
public struct KeychainStore: SecretStore {
    private let service: String
    private let account: String

    public init(service: String = "dev.hark.app", account: String = "model-key") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ secret: String) throws {
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = query
        add[kSecValueData as String] = data
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Loads and saves the settings with the model key kept in the Keychain. Everything that reads the
/// settings goes through here, so a command-line run sees the same key as the app.
public enum ConfigStore {
    private static let secrets = KeychainStore()

    /// Set in the environment of a test run that does not need the model key, so a freshly built command-line
    /// program does not ask for the login password to read it.
    private static var skipsKeychain: Bool { ProcessInfo.processInfo.environment["HARK_NO_KEYCHAIN"] != nil }

    public static func load(from url: URL = Paths.config) throws -> Config {
        let loaded = try Config.load(from: url)
        if skipsKeychain { return loaded }
        let result = ConfigSecrets.resolve(loaded: loaded, store: secrets)
        if let rewrite = result.rewrite { try? rewrite.save(to: url) }
        return result.inMemory
    }

    /// `clearing` is true only when the user has just emptied the key field.
    public static func save(_ config: Config, to url: URL = Paths.config, clearing: Bool = false) throws {
        if skipsKeychain { return }
        try ConfigSecrets.forDisk(config, store: secrets, clearing: clearing).save(to: url)
    }

    /// Puts an unreadable settings file aside before anything is written over it, so a typing mistake in a
    /// hand edit never costs the settings. Kept once; an earlier copy is left alone.
    public static func keepUnreadableFile(at url: URL = Paths.config) {
        let aside = url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".unreadable")
        guard FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: aside.path) else { return }
        try? FileManager.default.copyItem(at: url, to: aside)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: aside.path)
    }
}
