import HarkCore
import SwiftUI

struct LearningTab: View {
    let model: SettingsModel
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            GlassSection {
                Toggle("Learn from how I use my Mac", isOn: Binding(
                    get: { model.config.learns }, set: { model.setLearns($0) }))
                HelperText(
                    text: "Hark notes which apps and websites you switch between, never what is on them, and "
                        + "offers shortcuts. It all stays on this Mac.")
            }
            if model.config.learns {
                GlassSection {
                    Toggle("Let the AI model review commands that failed", isOn: Binding(
                        get: { model.config.reviewsFailures }, set: { model.setReviewsFailures($0) }))
                    HelperText(
                        text: "Uses the model you set up under Understanding. Only the words of commands Hark could "
                            + "not do are sent, which that model has already seen once. Its suggestions are tried "
                            + "out first and added only if you tap Add.")
                }
                findProjects
                noticed
                if !model.learned.accepted.isEmpty { learnedForYou }
                if !model.learned.deadEnds.isEmpty { deadEnds }
                GlassSection {
                    Button("Delete what Hark has noticed\u{2026}", role: .destructive) { confirmingDelete = true }
                } footer: {
                    HelperText(text: "Names, pages and routines you already added stay where they are.")
                }
            } else {
                GlassSection {
                    Text("Learning is off, so nothing is being noted.").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete what Hark has noticed?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { model.deleteLearning() }
        } message: {
            Text("This forgets the apps and websites Hark noted and the suggestions you dismissed.")
        }
        .task {
            while !Task.isCancelled {
                await model.refreshLearning()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private var findProjects: some View {
        GlassSection {
            HStack {
                Button("Find my projects") { Task { await model.findProjects() } }
                    .disabled(model.findingProjects)
                if model.findingProjects { ProgressView().controlSize(.small) }
                if let result = model.projectSearchResult, !model.findingProjects {
                    Label(result, systemImage: "checkmark.circle.fill")
                        .font(SettingsLayout.small)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            HelperText(
                text: "Looks for project folders, including on your Desktop and in Documents, so you can open them "
                    + "by name. macOS may ask you to allow it. Only folder names are read.")
        }
    }

    private var noticed: some View {
        GlassSection {
            if model.learned.suggestions.isEmpty {
                Text("Nothing yet. Hark needs a few days of use to spot habits.").foregroundStyle(.secondary)
            }
            ForEach(model.learned.suggestions) { suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    add: { model.acceptSuggestion(suggestion) },
                    notNow: { model.dismissSuggestion(suggestion, forever: false) },
                    never: { model.dismissSuggestion(suggestion, forever: true) })
            }
        } header: {
            Text("Hark noticed")
        } footer: {
            HelperText(text: "Nothing changes until you tap Add.")
        }
    }

    private var learnedForYou: some View {
        GlassSection {
            ForEach(model.learned.accepted) { item in
                HStack {
                    Image(systemName: SuggestionRow.symbol(for: item.kind)).foregroundStyle(.secondary).frame(width: 24)
                        .accessibilityHidden(true)
                    Text(item.title).lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Remove") { model.removeLearned(item.id) }
                        .accessibilityLabel("Remove \(item.title)")
                }
            }
        } header: {
            Text("Added for you")
        }
    }

    private var deadEnds: some View {
        GlassSection {
            ForEach(model.learned.deadEnds, id: \.phrase) { end in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\u{201C}\(end.phrase)\u{201D}").lineLimit(2)
                        if let topic = end.topic { HelperText(text: topic) }
                    }
                    Spacer(minLength: 8)
                    Text(end.count == 1 ? "once" : "\(end.count) times").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Asked for, could not do yet")
        } footer: {
            HelperText(text: "Only you see this. It shows what to improve next.")
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let add: () -> Void
    let notNow: () -> Void
    let never: () -> Void

    static func symbol(for kind: Suggestion.Kind) -> String {
        switch kind {
        case .name: "character.bubble"
        case .page: "globe"
        case .routine: "play.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.symbol(for: suggestion.kind))
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                HelperText(text: suggestion.detail)
                HStack(spacing: 8) {
                    Button("Add", action: add).buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Not now", action: notNow).controlSize(.small)
                    Button("Never", action: never).buttonStyle(.plain).foregroundStyle(.secondary)
                        .font(SettingsLayout.small)
                        .accessibilityHint("Hides this for good")
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
