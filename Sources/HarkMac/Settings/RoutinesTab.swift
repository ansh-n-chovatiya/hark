import HarkCore
import SwiftUI

struct RoutinesTab: View {
    let model: SettingsModel

    var body: some View {
        Form {
            RoutineList(model: model)
            if let routine = model.selectedRoutineDraft {
                RoutineEditor(model: model, routine: routine)
                    .id(EditorID(routine: routine.id))
            }
        }
        .formStyle(.grouped)
        // Switching tabs counts as having finished typing.
        .onDisappear(perform: model.finishEditingRoutine)
    }
}

/// The list's row for a routine already uses the routine's own id, and a form drops rows whose
/// ids repeat, so the editor needs one of its own.
private struct EditorID: Hashable {
    let routine: RoutineDraft.ID
}

private struct RoutineList: View {
    let model: SettingsModel
    @State private var isChoosingStarters = false

    var body: some View {
        let starters = model.missingStarterRoutines
        Section {
            if model.routines.isEmpty && model.removedRoutine == nil {
                Text("No routines yet. Add one for something you do every day, like opening your project folders.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 24)
            }
            ForEach(Array(model.routines.enumerated()), id: \.element.id) { index, routine in
                if let removed = model.removedRoutine, removed.index == index {
                    UndoRow(removed: removed, onUndo: model.undoRemoveRoutine)
                }
                RoutineRow(
                    routine: routine,
                    isSelected: routine.id == model.selectedRoutine,
                    needsFixing: model.showsProblem(in: routine)
                ) {
                    model.selectRoutine(routine.id)
                }
            }
            if let removed = model.removedRoutine, removed.index >= model.routines.count {
                UndoRow(removed: removed, onUndo: model.undoRemoveRoutine)
            }
            HStack {
                Button("Add routine", systemImage: "plus", action: model.addRoutine)
                Spacer(minLength: 12)
                if !starters.isEmpty {
                    Button("Add ready-made routines\u{2026}") {
                        isChoosingStarters = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Choose from routines that are already written")
                }
            }
            .sheet(isPresented: $isChoosingStarters) {
                StarterRoutinesSheet(routines: starters) { chosen in
                    model.addStarterRoutines(chosen)
                    isChoosingStarters = false
                } onCancel: {
                    isChoosingStarters = false
                }
            }
        } header: {
            Text("A routine is a list of steps you write once and run by name. Hark runs them exactly as written.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RoutineRow: View {
    let routine: RoutineDraft
    let isSelected: Bool
    let needsFixing: Bool
    let onSelect: () -> Void

    private static let markWidth: CGFloat = 20

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .frame(width: Self.markWidth)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(routine.typedName.isEmpty ? "New routine" : routine.typedName)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 12)
                summary
                    .font(SettingsLayout.small)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isSelected ? "This routine is shown below" : "Show this routine below")
    }

    private var summary: some View {
        HStack(spacing: 12) {
            if needsFixing {
                StatusLabel(text: "Not finished", symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            if routine.asksFirst {
                Label("\(stepCount), asks first", systemImage: "hand.raised.fill")
            } else {
                Text(stepCount)
            }
        }
    }

    private var stepCount: String {
        switch routine.steps.count {
        case 0: "No steps"
        case 1: "1 step"
        default: "\(routine.steps.count) steps"
        }
    }
}

private struct UndoRow: View {
    let removed: RemovedRoutine
    let onUndo: () -> Void

    private var name: String {
        removed.draft.typedName
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(name.isEmpty ? "Removed a routine." : "Removed \u{201C}\(name)\u{201D}.")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Button("Undo", action: onUndo)
        }
        .frame(minHeight: 24)
    }
}
