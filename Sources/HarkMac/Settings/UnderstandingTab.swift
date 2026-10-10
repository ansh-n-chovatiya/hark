import SwiftUI

struct UnderstandingTab: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Use an AI model for commands Hark\u{2019}s built-in rules cannot settle", isOn: useModel)
            }
            if model.config.useModel {
                onlineModel
                modelOnThisMac
            }
        }
        .formStyle(.grouped)
    }

    private var onlineModel: some View {
        Section {
            addressField(.online)
            SettingsTextField(
                "Model",
                text: model.config.model,
                helper: "Several names separated by commas are asked at once and the first answer is used."
            ) { name in
                model.update { $0.model = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            SettingsTextField("Key", text: model.config.modelKey, isSecret: true) { key in
                model.update { $0.modelKey = key.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        } header: {
            Text("Online model (optional)")
        } footer: {
            HelperText(
                text: "With an online model, your command and the names of open apps, windows, tabs and "
                    + "files are sent to that service. What you copy is never sent."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelOnThisMac: some View {
        Section {
            addressField(.onThisMac)
            SettingsTextField("Model", text: model.config.fallbackModel) { name in
                model.update { $0.fallbackModel = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        } header: {
            Text("Model on this Mac")
        } footer: {
            HelperText(text: "Used when the online model is slow or missing. Leave the model empty to turn this off.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func addressField(_ field: AddressField) -> some View {
        SettingsTextField(
            "Address",
            text: model.address(field),
            problem: model.rejectedAddresses[field]?.problem
        ) { address in
            model.setAddress(address, for: field)
        }
    }

    private var useModel: Binding<Bool> {
        Binding(get: { model.config.useModel }, set: { on in model.update { $0.useModel = on } })
    }
}
