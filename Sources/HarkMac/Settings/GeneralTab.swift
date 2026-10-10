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

    /// A line under a key that needs a word of warning. Hark steps aside if the key is used in a
    /// shortcut, but a key you press for shortcuts all day is a poor one to hold.
    private static let notes = [
        "fn": "Bottom-left key. Set \u{201C}Press \u{1F310} key to\u{201D} to Do Nothing in System Settings, Keyboard.",
        "leftControl": "Also part of many shortcuts",
        "leftOption": "Also part of many shortcuts",
        "leftCommand": "Also part of many shortcuts",
        "rightShift": "Also used for capital letters",
    ]

    var body: some View {
        Form {
            Section {
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
            notes: Self.notes, takenBy: taken(.hold),
            helper: "Hold it and speak.",
            problem: model.keyProblem(.hold), selection: key(.hold))
    }

    private var typingKeyPicker: some View {
        KeyPicker(
            title: "Key to tap for typing", keys: Self.keys + [("", "Off")], defaultKey: "rightCommand",
            notes: Self.notes, takenBy: taken(.typing),
            helper: "Tap it once to open a bar where you type a command.",
            problem: model.keyProblem(.typing), selection: key(.typing))
    }

    private var dictationKeyPicker: some View {
        KeyPicker(
            title: "Key to hold for dictation", keys: Self.keys + [("", "Off")], defaultKey: "",
            notes: Self.notes, takenBy: taken(.dictation),
            helper: "Hold it and speak: what you say is typed where your cursor is, in any app. "
                + "It types only your own words and never presses Return.",
            problem: model.keyProblem(.dictation), selection: key(.dictation))
    }

    private var loginToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            used[key] = switch other {
            case .hold: "Already used to speak"
            case .typing: "Already used to type"
            case .dictation: "Already used to dictate"
            }
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
    var notes: [String: String] = [:]
    var takenBy: [String: String] = [:]
    let helper: String
    let problem: String?
    @Binding var selection: String

    /// Not a key: the entry that puts the default back.
    private static let resetValue = "@reset"

    var body: some View {
        // A key set by hand in the settings file still has to be selectable.
        let known = keys.map {
            SelectOption(
                value: $0.0, title: $0.1, subtitle: $0.0 == recommended ? "Recommended" : notes[$0.0],
                unavailable: $0.0 == selection ? nil : takenBy[$0.0])
        }
        let extra = keys.contains { $0.0 == selection } ? [] : [SelectOption(value: selection, title: selection)]
        let defaultName = keys.first { $0.0 == defaultKey }?.1 ?? "Off"
        let reset = selection == defaultKey ? [] : [
            SelectOption(
                value: Self.resetValue, title: "Reset to default", subtitle: defaultName,
                symbol: "arrow.counterclockwise", unavailable: takenBy[defaultKey]),
        ]
        let chosen = Binding(
            get: { selection },
            set: { selection = $0 == Self.resetValue ? defaultKey : $0 })
        SettingsSelect(label: title, options: known + extra + reset, selection: chosen, helper: helper, problem: problem)
    }
}
