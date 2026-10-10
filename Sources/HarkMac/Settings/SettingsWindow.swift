import AppKit
import HarkCore

@MainActor public final class SettingsWindow {
    private let model: SettingsModel
    private var controller: SettingsWindowController?

    /// `onChange` is called with a complete, valid Config every time the user changes something.
    public init(
        config: Config,
        log: TimingLog,
        wrongLog: WrongLog = WrongLog(url: Paths.wrong),
        onChange: @escaping @MainActor (Config) -> Void
    ) {
        model = SettingsModel(config: config, system: .live(log: log, wrongLog: wrongLog), onChange: onChange)
    }

    public func show(_ section: SettingsSection = .general) {
        let controller = controller ?? SettingsWindowController(model: model)
        self.controller = controller
        controller.present(section)
    }

    /// Replaces what the window shows with a newer config, such as the settings file after it
    /// was changed by hand. Nothing is saved. Text the user typed that could not be saved yet
    /// stays in its field.
    public func reload(_ config: Config) {
        model.reload(config)
    }
}
