import HarkCore
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
            Picker("Service", selection: provider) {
                ForEach(ModelProvider.all) { Text($0.name).tag(Optional($0)) }
                Text("Other").tag(ModelProvider?.none)
            }
            addressField(.online)
            SettingsTextField("Key", text: model.config.modelKey, isSecret: true) { key in
                model.update { $0.modelKey = key.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            modelRow
            lookupStatus
        } header: {
            Text("Online model (optional)")
        } footer: {
            HelperText(
                text: "With an online model, your command and the names of open apps, windows, tabs and "
                    + "files are sent to that service. What you copy is never sent."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Looks the list up again when the service or the key changes, after a short pause so typing is not a request per letter.
        .task(id: "\(model.config.modelURL)\n\(model.config.modelKey)") {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await model.refreshModels()
        }
    }

    /// A menu with a tick beside each model when the service named its models, otherwise a box to
    /// type in. Every ticked model is asked at once and the first answer back is used.
    @ViewBuilder private var modelRow: some View {
        if case .found(let names) = model.modelLookup {
            let chosen = Self.names(in: model.config.model)
            LabeledContent("Models") {
                Menu {
                    // A model typed by hand that the service did not list stays ticked, so it is not lost.
                    ForEach(chosen.filter { !names.contains($0) } + names, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { chosen.contains(name) },
                            set: { on in setModel(name, on: on, from: chosen) }
                        ))
                    }
                } label: {
                    Text(summary(of: chosen))
                }
                .menuStyle(.button)
                .fixedSize()
            }
            HelperText(
                text: "Tick one or more. Hark asks them all at once and uses the first answer. "
                    + "Each ticked model is one more request to the service."
            )
        } else {
            SettingsTextField(
                "Model",
                text: model.config.model,
                helper: "Several names separated by commas are asked at once and the first answer is used."
            ) { name in
                model.update { $0.model = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
    }

    private static func names(in text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func summary(of chosen: [String]) -> String {
        switch chosen.count {
        case 0: "Choose models"
        case 1: chosen[0]
        default: "\(chosen[0]) + \(chosen.count - 1) more"
        }
    }

    /// The last ticked model cannot be unticked: with none, the online model would silently turn off.
    private func setModel(_ name: String, on: Bool, from chosen: [String]) {
        var updated = chosen
        if on, !updated.contains(name) { updated.append(name) }
        if !on, updated.count > 1 { updated.removeAll { $0 == name } }
        model.update { $0.model = updated.joined(separator: ", ") }
    }

    @ViewBuilder private var lookupStatus: some View {
        switch model.modelLookup {
        case .idle:
            EmptyView()
        case .needsKey:
            StatusLabel(text: "Add your key to see the models it can use.", symbol: "key.fill", tint: .orange)
                .font(SettingsLayout.small)
        case .looking:
            StatusLabel(text: "Looking up models\u{2026}", symbol: "ellipsis.circle", tint: .secondary)
                .font(SettingsLayout.small)
        case .found(let names):
            StatusLabel(
                text: "\(names.count) models available from your key.", symbol: "checkmark.circle.fill", tint: .green
            )
            .font(SettingsLayout.small)
        case .failed(let reason):
            HStack {
                ProblemText(text: reason)
                Spacer()
                Button("Try again") { Task { await model.refreshModels() } }
            }
        }
    }

    private var provider: Binding<ModelProvider?> {
        Binding(
            get: { ModelProvider.matching(address: model.config.modelURL) },
            set: { chosen in
                if let chosen { model.chooseProvider(chosen) }
            }
        )
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
