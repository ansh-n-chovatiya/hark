import Foundation

/// Somewhere a secret can be kept apart from the settings file, such as the macOS Keychain.
public protocol SecretStore: Sendable {
    func read() -> String?
    func write(_ secret: String) throws
    func delete()
}

/// Keeps the model key out of `config.json`. The settings file is easy to copy, share or commit by
/// accident; the Keychain is not. The key is held in memory in `Config.modelKey` as before, so nothing
/// else changes: this only decides where it is kept when the app is closed.
public enum ConfigSecrets {
    /// What to use now, and the settings to write back to the file (nil when the file is fine as it is).
    public static func resolve(loaded: Config, store: any SecretStore) -> (inMemory: Config, rewrite: Config?) {
        if !loaded.modelKey.isEmpty {
            // A key typed into the file by hand wins, and is moved out of it.
            guard keep(loaded.modelKey, in: store) else { return (loaded, nil) }
            var blank = loaded
            blank.modelKey = ""
            return (loaded, blank)
        }
        var config = loaded
        config.modelKey = store.read() ?? ""
        return (config, nil)
    }

    /// The settings as they go in the file: the key is kept in the store and left out. If the store
    /// refuses, the settings are returned as they are, so the key is never lost.
    public static func forDisk(_ config: Config, store: any SecretStore) -> Config {
        if config.modelKey.isEmpty {
            store.delete()
            return config
        }
        guard keep(config.modelKey, in: store) else { return config }
        var blank = config
        blank.modelKey = ""
        return blank
    }

    /// Writes the key and reads it back. Only a key that can be read again is allowed to leave the file.
    private static func keep(_ key: String, in store: any SecretStore) -> Bool {
        do {
            try store.write(key)
        } catch {
            return false
        }
        return store.read() == key
    }
}
