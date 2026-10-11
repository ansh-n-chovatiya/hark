import HarkCore
import SwiftUI

struct UnderstandingTab: View {
    let model: SettingsModel

    var body: some View {
        Form {
            GlassSection {
                Toggle("Use an AI model for commands Hark\u{2019}s built-in rules cannot settle", isOn: useModel)
            }
            if model.config.useModel {
                onlineModel
                modelOnThisMac
                if let tool = ModelCLIs.found.first { commandLineTool(tool) }
                aiTools
                terminal
            }
        }
        .formStyle(.grouped)
    }

    private var terminal: some View {
        GlassSection {
            Toggle("Let Hark run terminal commands for me", isOn: Binding(
                get: { model.config.terminalCommands }, set: { model.setTerminalCommands($0) }))
            HelperText(
                text: "For tasks only the terminal can do, such as \u{201C}what is using port 3000\u{201D}. Hark shows "
                    + "the exact command and runs it only after you say yes. It cannot delete or move anything, and "
                    + "what it prints stays on this Mac.")
            if model.config.terminalCommands {
                Toggle("Also let those commands change files and use the network", isOn: Binding(
                    get: { model.config.terminalChanges }, set: { model.setTerminalChanges($0) }))
                HelperText(
                    text: "Needed for things like git pull or installing a tool. Commands still cannot delete, move "
                        + "or rename files, but they can create and overwrite them.")
            }
        }
    }

    private var onlineModel: some View {
        GlassSection {
            SettingsSelect(
                label: "Service",
                options: ModelProvider.all.map { SelectOption(value: Optional($0), title: $0.name) }
                    + [SelectOption(value: nil, title: "Other", subtitle: "Type the address yourself")],
                selection: provider)
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
            // A model typed by hand that the service did not list stays in the list, so it is not lost.
            let unlisted = chosen.filter { !names.contains($0) }
                .map { SelectOption(value: $0, title: $0, subtitle: "Not listed by the service") }
            SettingsMultiSelect(
                label: "Models",
                options: unlisted + names.map { SelectOption(value: $0, title: $0) },
                selection: Binding(
                    get: { chosen },
                    set: { picked in model.update { $0.model = picked.joined(separator: ", ") } }),
                placeholder: "Choose models",
                helper: "Tick one or more. Hark asks them all at once and uses the first answer. "
                    + "Each ticked model is one more request to the service.")
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

    /// The AI command-line tool found on this Mac, and which of its models Hark asks.
    private func commandLineTool(_ tool: ModelCLI) -> some View {
        GlassSection {
            SettingsSelect(
                label: "Model",
                options: Self.toolModels(including: model.config.cliModel),
                selection: Binding(
                    get: { model.config.cliModel },
                    set: { name in model.update { $0.cliModel = name } }))
        } header: {
            Text(tool.label)
        } footer: {
            HelperText(
                text: "Found on this Mac. Hark starts it for each question with its own tools off, so it can only answer in "
                    + "words. Larger models usually take longer to answer.")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The tool's own short names, with a star on the fastest, and a model typed into the settings file by hand.
    private static func toolModels(including current: String) -> [SelectOption<String>] {
        let known = [
            SelectOption(value: "haiku", title: "Haiku", subtitle: "Fastest", trailingSymbol: "star.fill"),
            SelectOption(value: "sonnet", title: "Sonnet", subtitle: "Balanced"),
            SelectOption(value: "opus", title: "Opus", subtitle: "Most capable"),
        ]
        return known.contains { $0.value == current } ? known : known + [SelectOption(value: current, title: current)]
    }

    /// The order models are tried in, which are turned on, and which is resting after a failure.
    private var aiTools: some View {
        GlassSection {
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                let entries = ModelSetup.entries(for: model.config)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(entries.enumerated()), id: \.element.key) { index, entry in
                        ChainRow(
                            number: index + 1, label: entry.choice.label, isOn: entry.isOn,
                            down: ModelHealth.shared.status(of: entry.choice.id),
                            canMoveUp: index > 0, canMoveDown: index < entries.count - 1,
                            setOn: { model.setModel(entry.key, on: $0) },
                            move: { model.moveModel(entry.key, by: $0) })
                    }
                    if entries.isEmpty { Text("No model is set up.").foregroundStyle(.secondary) }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Order Hark tries")
        } footer: {
            HelperText(
                text: (ModelCLIs.found.isEmpty ? "No AI command-line tool was found; Hark looks for Claude Code. " : "")
                    + "The first one that works answers. One that fails, such as for being out of quota, is skipped for a "
                    + "while. Your command words and the names of open apps go to the service behind any online model or tool. "
                    + "Turn one off to keep it from being used.")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelOnThisMac: some View {
        GlassSection {
            addressField(.onThisMac)
            localModelRow
            localStatus
        } header: {
            Text("Model on this Mac")
        } footer: {
            HelperText(text: "Used when the online model is slow or missing. Choose Off to turn this off.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Looked up again when the address changes, after a short pause so typing is not a request per letter.
        .task(id: model.config.fallbackModelURL) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await model.refreshLocalModels()
        }
    }

    /// A list of what is installed at that address, or a box to type in when it cannot be read.
    @ViewBuilder private var localModelRow: some View {
        if case .found(let names) = model.localLookup {
            let current = model.config.fallbackModel
            let missing = !current.isEmpty && !names.contains(current)
            SettingsSelect(
                label: "Model",
                options: (missing ? [SelectOption(value: current, title: current, unavailable: "Not installed")] : [])
                    + names.map { SelectOption(value: $0, title: $0) }
                    + [SelectOption(value: "", title: "Off", symbol: "nosign", separatorBefore: true)],
                selection: Binding(
                    get: { current },
                    set: { name in model.update { $0.fallbackModel = name } }))
        } else {
            SettingsTextField("Model", text: model.config.fallbackModel) { name in
                model.update { $0.fallbackModel = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
    }

    @ViewBuilder private var localStatus: some View {
        let current = model.config.fallbackModel
        switch model.localLookup {
        case .idle, .needsKey:
            EmptyView()
        case .looking:
            StatusLabel(text: "Looking for models\u{2026}", symbol: "ellipsis.circle", tint: .secondary)
                .font(SettingsLayout.small)
        case .found(let names):
            if !current.isEmpty, !names.contains(current) {
                ProblemText(
                    text: "\u{201C}\(current)\u{201D} is not installed at this address. Choose one from the list, or install it "
                        + "first (with Ollama: ollama pull \(current)).")
            } else {
                StatusLabel(
                    text: names.count == 1 ? "1 model installed here." : "\(names.count) models installed here.",
                    symbol: "checkmark.circle.fill", tint: .green)
                    .font(SettingsLayout.small)
            }
        case .failed(let reason):
            HStack {
                ProblemText(text: reason + " If you use Ollama, make sure it is running.")
                Spacer()
                Button("Try again") { Task { await model.refreshLocalModels() } }
            }
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

private struct ChainRow: View {
    let number: Int
    let label: String
    let isOn: Bool
    let down: ModelHealth.Down?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let setOn: (Bool) -> Void
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)").foregroundStyle(.secondary).frame(width: 18)
            Text(label).foregroundStyle(isOn ? .primary : .secondary)
            Spacer(minLength: 8)
            if !isOn {
                StatusLabel(text: "Off", symbol: "minus.circle", tint: .secondary).font(SettingsLayout.small)
            } else if let down {
                StatusLabel(
                    text: "\(down.reason), resting until \(down.until.formatted(date: .omitted, time: .shortened))",
                    symbol: "pause.circle.fill", tint: .orange)
                    .font(SettingsLayout.small)
            } else {
                StatusLabel(text: "Ready", symbol: "checkmark.circle.fill", tint: .green).font(SettingsLayout.small)
            }
            Toggle(label, isOn: Binding(get: { isOn }, set: setOn))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                    .accessibilityLabel("Try \(label) earlier")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
                    .accessibilityLabel("Try \(label) later")
            }
            .buttonStyle(.borderless)
        }
    }
}
