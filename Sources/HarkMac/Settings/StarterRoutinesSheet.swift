import HarkCore
import SwiftUI

/// The ready-made routines the user does not have yet, to tick and add in one go.
struct StarterRoutinesSheet: View {
    let routines: [Routine]
    let onAdd: ([Routine]) -> Void
    let onCancel: () -> Void

    @State private var chosen: Set<String>

    init(routines: [Routine], onAdd: @escaping ([Routine]) -> Void, onCancel: @escaping () -> Void) {
        self.routines = routines
        self.onAdd = onAdd
        self.onCancel = onCancel
        _chosen = State(initialValue: Set(routines.map(\.name)))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                GlassSection {
                    ForEach(routines, id: \.name) { routine in
                        StarterRoutineRow(routine: routine, isChosen: isChosen(routine.name))
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add ready-made routines")
                        Group {
                            Text("These are ordinary routines. You can read and change every one after adding it.")
                            Text(
                                "The GitHub ones need the gh tool and \u{201C}ask claude\u{201D} needs the claude tool, "
                                    + "each already signed in.")
                        }
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(routines.filter { chosen.contains($0.name) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 560, height: 560)
    }

    private func isChosen(_ name: String) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(name) },
            set: { on in
                if on {
                    chosen.insert(name)
                } else {
                    chosen.remove(name)
                }
            })
    }
}

private struct StarterRoutineRow: View {
    let routine: Routine
    @Binding var isChosen: Bool

    private var command: String {
        routine.steps.compactMap { $0.shell ?? $0.say }.joined(separator: "\n")
    }

    var body: some View {
        Toggle(isOn: $isChosen) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    Text(routine.name)
                    Spacer(minLength: 12)
                    if routine.steps.contains(where: \.destructive) {
                        Label("Asks first", systemImage: "hand.raised.fill")
                            .font(SettingsLayout.small)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(command)
                    .font(SettingsLayout.small.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }
}
