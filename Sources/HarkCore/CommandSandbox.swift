import Foundation

/// The limits a terminal command runs under, enforced by macOS (sandbox-exec), not by reading the command: whatever
/// it says, it cannot go past them.
public enum CommandSandbox {
    /// Read-only: nothing is written, deleted or moved anywhere (apart from temporary files), and there is no network.
    /// With `allowingChanges` files can be created and written and the network is open, but nothing can be deleted,
    /// moved or renamed.
    public static func profile(allowingChanges: Bool) -> String {
        if allowingChanges {
            return "(version 1)(allow default)(deny file-write-unlink)"
        }
        return "(version 1)(allow default)(deny file-write*)"
            + "(allow file-write* (literal \"/dev/null\") (literal \"/dev/tty\") (subpath \"/private/var/folders\") (subpath \"/private/tmp\"))"
            + "(deny network*)"
    }

    /// The program and arguments that run `command` under the profile.
    public static func arguments(running command: String, allowingChanges: Bool) -> (executable: String, arguments: [String]) {
        ("/usr/bin/sandbox-exec", ["-p", profile(allowingChanges: allowingChanges), "/bin/zsh", "-lc", command])
    }
}
