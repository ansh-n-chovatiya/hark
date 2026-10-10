import SwiftUI

struct GeneralTab: View {
    let model: SettingsModel

    private static let keys = [
        ("rightOption", "Right Option (recommended)"),
        ("rightCommand", "Right Command"),
        ("rightControl", "Right Control"),
        ("f13", "F13"),
        ("f14", "F14"),
        ("f15", "F15"),
    ]

    var body: some View {
        Form {
            Section {
                holdKeyPicker
                typingKeyPicker
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
            title: "Key to hold", keys: Self.keys, helper: "Hold it and speak.",
            problem: model.keyProblem(.hold), selection: key(.hold))
    }

    private var typingKeyPicker: some View {
        KeyPicker(
            title: "Key to tap for typing", keys: Self.keys + [("", "Off")],
            helper: "Tap it once to open a bar where you type a command.",
            problem: model.keyProblem(.typing), selection: key(.typing))
    }

    private var loginToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Start Hark when you log in", isOn: loginItem)
            if let problem = model.loginItemProblem {
                ProblemText(text: problem)
            }
        }
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
    let helper: String
    let problem: String?
    @Binding var selection: String

    var body: some View {
        // A key set by hand in the settings file still has to be selectable.
        let known = keys.map { SelectOption(value: $0.0, title: $0.1) }
        let extra = keys.contains { $0.0 == selection } ? [] : [SelectOption(value: selection, title: selection)]
        SettingsSelect(label: title, options: known + extra, selection: $selection, helper: helper, problem: problem)
    }
}
