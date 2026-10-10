import HarkCore
import ServiceManagement

/// Everything the settings read from or change on the Mac outside the config, so the previews can
/// show sample states without touching login items, permissions, the history file or the list of
/// commands that went wrong.
struct SettingsSystem: Sendable {
    var permissionStatus: @Sendable (Permission) -> PermissionStatus
    var openPermissionSettings: @MainActor @Sendable (Permission) -> Void
    var loginItemIsOn: @MainActor @Sendable () -> Bool
    var setLoginItem: @MainActor @Sendable (Bool) throws -> Void
    var history: @Sendable () -> [Timings]
    var reports: @Sendable () -> [WrongLog.Entry]
    var report: @Sendable (WrongLog.Entry) -> Void

    static func live(log: TimingLog, wrongLog: WrongLog) -> SettingsSystem {
        SettingsSystem(
            permissionStatus: { Permissions.status($0) },
            openPermissionSettings: { Permissions.openSettings(for: $0) },
            loginItemIsOn: { SMAppService.mainApp.status == .enabled },
            setLoginItem: { on in
                if on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            },
            history: { log.all() },
            reports: { wrongLog.all() },
            report: { wrongLog.append($0) }
        )
    }
}
