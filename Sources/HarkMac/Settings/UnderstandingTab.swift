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

    /// A list to choose from when the service named its models, otherwise a box to type in. Several
    /// names separated by commas are still allowed, so a comma list always shows as text.
    @ViewBuilder private var modelRow: some View {
        if case .found(let names) = model.modelLookup, !model.config.model.contains(",") {
            let current = model.config.model
            Picker("Model", selection: Binding(
                get: { current },
                set: { name in model.update { $0.model = name } }
            )) {
                if current.isEmpty { Text("Choose a model").tag("") }
                if !current.isEmpty, !names.contains(current) { Text("\(current) (not listed)").tag(current) }
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
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
