import SwiftUI

struct GeneralTab: View {
    let model: SettingsModel

    /// Keys Hark can listen for. Apple's own keyboards have no right Control, so it is left out.
    /// F13 to F15 are for external keyboards.
    private static let keys = [
        ("fn", "fn (Globe)"),
        ("leftControl", "Left Control"),
        ("leftOption", "Left Option"),
        ("leftCommand", "Left Command"),
        ("rightOption", "Right Option"),
        ("rightCommand", "Right Command"),
        ("rightShift", "Right Shift"),
        ("f13", "F13"),
        ("f14", "F14"),
        ("f15", "F15"),
    ]

    /// Said under the field when the chosen key needs a word of explanation.
    private static let longNotes = [
        "fn": "Also set \u{201C}Press \u{1F310} key to\u{201D} to Do Nothing in Keyboard settings.",
    ]

    var body: some View {
        Form {
            GlassSection {
                holdKeyPicker
                typingKeyPicker
                dictationKeyPicker
                loginToggle
            }
            FolderList(
                title: "Folders Hark can open by name",
                folders: model.config.searchFolders,
                emptyText: "No folders yet. Add the folder your projects live in.",
                helper: "Hark looks inside these for files and folders you name."
            ) { folders in
                model.update { $0.searchFolders = folders }
            }
            FolderList(
                title: "Projects you name often",
                folders: model.config.repos,
                emptyText: "No projects yet. Add a project folder you open a lot.",
                helper: "You can say these by name, like \u{201C}open the backend project\u{201D}."
            ) { folders in
                model.update { $0.repos = folders }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: model.refreshLoginItem)
    }

    private var holdKeyPicker: some View {
        KeyPicker(
            title: "Key to hold", keys: Self.keys, recommended: "rightOption", defaultKey: "rightOption",
            longNotes: Self.longNotes, takenBy: taken(.hold),
            helper: "Hold it and speak. The star marks the recommended key.",
            problem: model.keyProblem(.hold), selection: key(.hold))
    }

    private var typingKeyPicker: some View {
        KeyPicker(
            title: "Key to tap for typing", keys: Self.keys + [("", "Off")], defaultKey: "rightCommand",
            longNotes: Self.longNotes, takenBy: taken(.typing),
            helper: "Tap it to type a command.",
            problem: model.keyProblem(.typing), selection: key(.typing))
    }

    private var dictationKeyPicker: some View {
        KeyPicker(
            title: "Key to hold for dictation", keys: Self.keys + [("", "Off")], defaultKey: "",
            longNotes: Self.longNotes, takenBy: taken(.dictation),
            helper: "Hold it and speak. Your words are typed where the cursor is.",
            problem: model.keyProblem(.dictation), selection: key(.dictation))
    }

    private var loginToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Say punctuation while dictating", isOn: Binding(
                get: { model.config.spokenPunctuation }, set: { model.setSpokenPunctuation($0) }))
            HelperText(text: "\u{201C}Hello comma world full stop\u{201D} types \u{201C}Hello, world.\u{201D} Also: question mark, capital, all caps, no space.")
            Toggle("Start Hark when you log in", isOn: loginItem)
            if let problem = model.loginItemProblem {
                ProblemText(text: problem)
            }
        }
    }

    /// Keys another action already uses, with what that action is, so they cannot be picked twice.
    private func taken(_ field: KeyField) -> [String: String] {
        var used: [String: String] = [:]
        for other in KeyField.allCases where other != field {
            let key = model.key(other)
            guard !key.isEmpty else { continue }
            used[key] = "In use"
        }
        return used
    }

    private func key(_ field: KeyField) -> Binding<String> {
        Binding(get: { model.key(field) }, set: { model.setKey($0, for: field) })
    }

    private var loginItem: Binding<Bool> {
        Binding(get: { model.loginItemIsOn }, set: { model.setLoginItem($0) })
    }
}

private struct KeyPicker: View {
    let title: String
    let keys: [(String, String)]
    var recommended: String?
    /// What "Reset to default" puts back.
    let defaultKey: String
    var longNotes: [String: String] = [:]
    var takenBy: [String: String] = [:]
    let helper: String
    let problem: String?
    @Binding var selection: String

    /// The symbol macOS draws on that key's cap.
    private static func symbol(forKey key: String) -> String? {
        let name = key.lowercased()
        if name == "fn" { return "globe" }
        if name.hasSuffix("control") { return "control" }
        if name.hasSuffix("option") { return "option" }
        if name.hasSuffix("command") { return "command" }
        if name.hasSuffix("shift") { return "shift" }
        if name.hasPrefix("f1") { return "keyboard" }
        if key.isEmpty { return "nosign" }
        return nil
    }

    /// Not a key: the entry that puts the default back.
    private static let resetValue = "@reset"

    var body: some View {
        // A key set by hand in the settings file still has to be selectable.
        let known = keys.map { key in
            SelectOption(
                value: key.0, title: key.1,
                symbol: Self.symbol(forKey: key.0),
                unavailable: key.0 == selection ? nil : takenBy[key.0],
                trailingSymbol: key.0 == recommended ? "star.fill" : nil,
                separatorBefore: key.0.isEmpty)
        }
        let extra = keys.contains { $0.0 == selection } ? [] : [SelectOption(value: selection, title: selection)]
        let reset = selection == defaultKey ? [] : [
            SelectOption(
                value: Self.resetValue, title: "Reset to default", symbol: "arrow.counterclockwise",
                unavailable: takenBy[defaultKey]),
        ]
        let chosen = Binding(
            get: { selection },
            set: { selection = $0 == Self.resetValue ? defaultKey : $0 })
        SettingsSelect(
            label: title, options: known + extra + reset, selection: chosen,
            helper: [helper, longNotes[selection]].compactMap { $0 }.joined(separator: " "), problem: problem)
    }
}
