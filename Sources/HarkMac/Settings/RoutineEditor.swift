import SwiftUI

/// The name and steps of the routine chosen in the list.
struct RoutineEditor: View {
    let model: SettingsModel
    let routine: RoutineDraft

    var body: some View {
        Section {
            SettingsTextField(
                "Name",
                text: routine.name,
                helper: "Say or type this name to run it.",
                problem: model.nameProblem(of: routine)
            ) { name in
                model.editRoutine(routine.id) {
                    $0.name = name
                    $0.nameWasEdited = true
                }
            }
        } header: {
            Text(routine.typedName.isEmpty ? "New routine" : routine.typedName)
        }
        ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
            StepSection(
                model: model, routine: routine.id, step: step, number: index + 1, count: routine.steps.count)
        }
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Button("Add step", systemImage: "plus") {
                    model.editRoutine(routine.id) { $0.steps.append(StepDraft()) }
                }
                if let problem = routine.stepsProblem {
                    ProblemText(text: problem)
                }
            }
        }
        Section {
            Button("Remove this routine", systemImage: "minus.circle") {
                model.removeRoutine(routine.id)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        } footer: {
            HelperText(text: "You can undo this for a few seconds.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StepSection: View {
    let model: SettingsModel
    let routine: RoutineDraft.ID
    let step: StepDraft
    let number: Int
    let count: Int

    private static let placeholdersHelp =
        "{arg} is what you say after the name. Say \u{201C}stop port 8002\u{201D} and {arg} is 8002.\n"
        + "{repo} repeats the step for each of your projects, like git -C {repo} pull."

    private var isShell: Bool {
        step.kind == .shell
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Kind", selection: kind) {
                    Text("Hark command").tag(StepKind.hark)
                    Text("Shell command").tag(StepKind.shell)
                }
                HelperText(text: isShell ? "A command you would type in Terminal." : "Something you would say to Hark.")
            }
            SettingsTextField(
                isShell ? "Command" : "What to say",
                text: step.text,
                helper: isShell ? Self.placeholdersHelp : nil,
                problem: model.textProblem(of: step),
                isCode: isShell
            ) { text in
                edit {
                    $0.text = text
                    $0.textWasEdited = true
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Ask before running", isOn: asksFirst)
                HelperText(text: "Turn this on for anything that stops, changes or removes something.")
            }
            if isShell {
                SettingsTextField(
                    "Stop after",
                    text: step.stopAfter,
                    helper: "How many seconds this step may take. Leave it empty for 30.",
                    problem: model.stopAfterProblem(of: step),
                    prompt: "30"
                ) { seconds in
                    edit {
                        $0.stopAfter = seconds
                        $0.stopAfterWasEdited = true
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("Step \(number)")
                Spacer(minLength: 12)
                StepButton(title: "Move step \(number) up", symbol: "arrow.up") {
                    model.moveStep(step.id, in: routine, by: -1)
                }
                .disabled(number == 1)
                StepButton(title: "Move step \(number) down", symbol: "arrow.down") {
                    model.moveStep(step.id, in: routine, by: 1)
                }
                .disabled(number == count)
                StepButton(title: "Remove step \(number)", symbol: "minus.circle") {
                    model.editRoutine(routine) { $0.steps.removeAll { $0.id == step.id } }
                }
            }
        }
    }

    private var kind: Binding<StepKind> {
        Binding(get: { step.kind }, set: { kind in edit { $0.kind = kind } })
    }

    private var asksFirst: Binding<Bool> {
        Binding(get: { step.asksFirst }, set: { on in edit { $0.asksFirst = on } })
    }

    private func edit(_ change: (inout StepDraft) -> Void) {
        model.editStep(step.id, in: routine, change)
    }
}

private struct StepButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(title)
    }
}
