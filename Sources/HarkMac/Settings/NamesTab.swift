import SwiftUI

struct NamesTab: View {
    @Bindable var model: SettingsModel
    @FocusState private var focus: NameFocus?

    var body: some View {
        Form {
            NamePairs(
                rows: $model.names,
                focus: $focus,
                words: .ownWords,
                onAdd: model.addName,
                onRemove: model.removeName,
                onFinish: model.finishEditingName
            )
            NamePairs(
                rows: $model.links,
                focus: $focus,
                words: .webPages,
                onAdd: model.addLink,
                onRemove: model.removeLink,
                onFinish: model.finishEditingLink
            )
        }
        .formStyle(.grouped)
        .onChange(of: focus) { old, new in
            guard let old else { return }
            if case .meant(let id) = old {
                model.finishLinkAddress(id)
            }
            if old.row != new?.row {
                model.finishEditingName(old.row)
                model.finishEditingLink(old.row)
            }
        }
        // Switching tabs removes the fields before they hear that they lost focus.
        .onDisappear {
            model.saveNames()
            model.saveLinks()
        }
    }
}

/// The words that differ between the two groups of pairs in this tab.
private struct PairWords {
    let title: String
    let meantTitle: String
    let saidPrompt: String
    let meantPrompt: String
    let emptyText: String
    let addTitle: String
    let removeTitle: String
    let helper: String

    static let ownWords = PairWords(
        title: "Your own words",
        meantTitle: "I mean",
        saidPrompt: "the backend",
        meantPrompt: "shop-backend",
        emptyText: "Teach Hark your own names, like \u{201C}the backend\u{201D} for a folder.",
        addTitle: "Add a name",
        removeTitle: "Remove this name",
        helper: "When you say the words on the left, Hark hears the words on the right."
    )

    static let webPages = PairWords(
        title: "Web pages by name",
        meantTitle: "Open this address",
        saidPrompt: "the task board",
        meantPrompt: "https://tracker.example.com/board",
        emptyText: "No pages yet. Add one you open every day.",
        addTitle: "Add a page",
        removeTitle: "Remove this page",
        helper: "Say \u{201C}open\u{201D} and the name, like \u{201C}open the task board\u{201D}."
    )
}

private struct NamePairs: View {
    @Binding var rows: [NameRow]
    var focus: FocusState<NameFocus?>.Binding
    let words: PairWords
    let onAdd: () -> NameRow.ID
    let onRemove: (NameRow.ID) -> Void
    let onFinish: (NameRow.ID) -> Void

    private static let saidTitle = "When I say"
    private static let arrowWidth: CGFloat = 20
    private static let removeWidth: CGFloat = 24

    var body: some View {
        GlassSection {
            if rows.isEmpty {
                Text(words.emptyText)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 24)
            } else {
                columnTitles
            }
            // Rows are bound by identity, not position: see RowBinding.
            ForEach(rows) { row in
                pairRow(RowBinding.make($rows, id: row.id, placeholder: row))
            }
            Button(words.addTitle, systemImage: "plus") {
                focus.wrappedValue = .said(onAdd())
            }
        } header: {
            Text(words.title)
        } footer: {
            HelperText(text: words.helper)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var columnTitles: some View {
        HStack(spacing: 8) {
            Text(Self.saidTitle).frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: Self.arrowWidth, height: 1)
            Text(words.meantTitle).frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: Self.removeWidth, height: 1)
        }
        .font(SettingsLayout.small.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func pairRow(_ row: Binding<NameRow>) -> some View {
        let id = row.wrappedValue.id
        let said = row.wrappedValue.said
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(Self.saidTitle, text: row.said, prompt: Text(words.saidPrompt))
                    .focused(focus, equals: .said(id))
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .frame(width: Self.arrowWidth)
                    .accessibilityHidden(true)
                TextField(words.meantTitle, text: row.meant, prompt: Text(words.meantPrompt))
                    .focused(focus, equals: .meant(id))
                Button {
                    onRemove(id)
                } label: {
                    Label(said.isEmpty ? words.removeTitle : "Remove \(said)", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                        .frame(width: Self.removeWidth, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(words.removeTitle)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .onSubmit { onFinish(id) }
            if let problem = row.wrappedValue.problem {
                ProblemText(text: problem)
            }
        }
    }
}

private enum NameFocus: Hashable {
    case said(NameRow.ID)
    case meant(NameRow.ID)

    var row: NameRow.ID {
        switch self {
        case .said(let id), .meant(let id): id
        }
    }
}
