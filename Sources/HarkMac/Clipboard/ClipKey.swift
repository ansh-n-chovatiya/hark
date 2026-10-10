import CryptoKit
import Foundation
import HarkCore

/// The key that encrypts clipboard history, kept in a file only this user can read.
///
/// It was in the Keychain first, but macOS ties a Keychain item to the exact build that made it,
/// so every rebuild of a self-signed app stopped at a password prompt. The file is left out of
/// backups, so a backup of the history alone stays unreadable.
public enum ClipKey {
    public static func loadOrCreate() throws -> SymmetricKey {
        var url = Paths.support.appending(path: "clips.key")
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try key.withUnsafeBytes { Data($0) }.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return key
    }
}
