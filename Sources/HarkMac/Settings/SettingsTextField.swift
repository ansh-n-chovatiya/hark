import SwiftUI

/// A labelled text box that hands its text over when the user leaves it or presses Return, with
/// the problem and the helper text underneath.
struct SettingsTextField: View {
    let label: String
    let text: String
    var helper: String?
    var problem: String?
    var isSecret = false
    var isCode = false
    var prompt: String?
    let onCommit: (String) -> Void

    @State private var draft: String
    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    init(
        _ label: String,
        text: String,
        helper: String? = nil,
        problem: String? = nil,
        isSecret: Bool = false,
        isCode: Bool = false,
        prompt: String? = nil,
        onCommit: @escaping (String) -> Void
    ) {
        self.label = label
        self.text = text
        self.helper = helper
        self.problem = problem
        self.isSecret = isSecret
        self.isCode = isCode
        self.prompt = prompt
        self.onCommit = onCommit
        _draft = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(label) {
                HStack(spacing: 6) {
                    field
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .font(isCode ? .body.monospaced() : nil)
                        .focused($isFocused)
                        .modifier(HarkField(focused: $isFocused))
                        .onSubmit(commit)
                    if isSecret {
                        revealButton
                    }
                }
                .frame(width: SettingsLayout.fieldWidth)
            }
            if let problem {
                ProblemText(text: problem)
            }
            if let helper {
                HelperText(text: helper)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onChange(of: text) { _, text in
            draft = text
        }
        // Switching tabs removes the field before it hears that it lost focus.
        .onDisappear(perform: commit)
    }

    @ViewBuilder private var field: some View {
        if isSecret && !isRevealed {
            SecureField(label, text: $draft)
        } else {
            TextField(label, text: $draft, prompt: prompt.map(Text.init))
        }
    }

    private var revealButton: some View {
        let title = isRevealed ? "Hide \(label.lowercased())" : "Show \(label.lowercased())"
        return Button {
            isRevealed.toggle()
        } label: {
            Label(title, systemImage: isRevealed ? "eye.slash" : "eye")
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    private func commit() {
        guard draft != text else { return }
        onCommit(draft)
    }
}
