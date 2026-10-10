import Foundation
import HarkCore

extension SettingsModel {
    static let undoTime = Duration.seconds(8)

    var selectedRoutineDraft: RoutineDraft? {
        routines.first { $0.id == selectedRoutine }
    }

    // MARK: Problems, as shown

    func nameProblem(of routine: RoutineDraft) -> String? {
        routine.nameWasEdited ? routine.nameProblem(taken: namesTaken(before: routine.id)) : nil
    }

    func textProblem(of step: StepDraft) -> String? {
        step.textWasEdited ? step.textProblem : nil
    }

    func stopAfterProblem(of step: StepDraft) -> String? {
        step.stopAfterWasEdited ? step.stopAfterProblem : nil
    }

    func showsProblem(in routine: RoutineDraft) -> Bool {
        nameProblem(of: routine) != nil || routine.stepsProblem != nil
            || routine.steps.contains { textProblem(of: $0) != nil || stopAfterProblem(of: $0) != nil }
    }

    /// The earlier of two routines with one name keeps it.
    private func namesTaken(before id: RoutineDraft.ID) -> [String] {
        routines.prefix { $0.id != id }.map(\.typedName)
    }

    // MARK: Changes

    func addRoutine() {
        let routine = RoutineDraft()
        routines.append(routine)
        selectRoutine(routine.id)
    }

    var missingStarterRoutines: [Routine] {
        StarterRoutines.missing(from: routines.map(\.routine))
    }

    /// Ready-made routines are added as if they had just been typed, so they are checked and
    /// saved the same way.
    func addStarterRoutines(_ chosen: [Routine]) {
        let added = chosen.map { routine in
            var draft = RoutineDraft(routine)
            draft.onFile = nil
            return draft
        }
        routines.append(contentsOf: added)
        if selectedRoutineDraft == nil {
            selectedRoutine = added.first?.id
        }
        saveRoutines()
    }

    func selectRoutine(_ id: RoutineDraft.ID?) {
        guard id != selectedRoutine else { return }
        finishEditingRoutine()
        selectedRoutine = id
    }

    /// Moving on from a routine counts as having finished typing in all of it.
    func finishEditingRoutine() {
        guard let index = routines.firstIndex(where: { $0.id == selectedRoutine }) else { return }
        routines[index].showAllProblems()
    }

    func editRoutine(_ id: RoutineDraft.ID, _ change: (inout RoutineDraft) -> Void) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        change(&routines[index])
        saveRoutines()
    }

    func editStep(_ id: StepDraft.ID, in routine: RoutineDraft.ID, _ change: (inout StepDraft) -> Void) {
        editRoutine(routine) { routine in
            guard let index = routine.steps.firstIndex(where: { $0.id == id }) else { return }
            change(&routine.steps[index])
        }
    }

    func moveStep(_ id: StepDraft.ID, in routine: RoutineDraft.ID, by offset: Int) {
        editRoutine(routine) { routine in
            guard let index = routine.steps.firstIndex(where: { $0.id == id }),
                routine.steps.indices.contains(index + offset)
            else { return }
            routine.steps.swapAt(index, index + offset)
        }
    }

    func removeRoutine(_ id: RoutineDraft.ID) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        removedRoutine = RemovedRoutine(draft: routines.remove(at: index), index: index)
        if selectedRoutine == id {
            selectedRoutine = routines.indices.contains(index) ? routines[index].id : routines.last?.id
        }
        saveRoutines()
        Task { [weak self] in
            try? await Task.sleep(for: Self.undoTime)
            if self?.removedRoutine?.draft.id == id {
                self?.removedRoutine = nil
            }
        }
    }

    func undoRemoveRoutine() {
        guard let removed = removedRoutine else { return }
        removedRoutine = nil
        routines.insert(removed.draft, at: min(removed.index, routines.count))
        selectedRoutine = removed.draft.id
        saveRoutines()
    }

    // MARK: Saving and reading

    /// Hands over every routine that is complete. One that is not keeps the version the file
    /// already holds, if there is one, until it is fixed.
    func saveRoutines() {
        var saved: [Routine] = []
        var taken: [String] = []
        for index in routines.indices {
            let draft = routines[index]
            if draft.isUntouched, let onFile = draft.onFile {
                saved.append(onFile)
            } else if draft.isComplete(taken: taken) {
                routines[index].onFile = draft.routine
                saved.append(draft.routine)
            } else if let onFile = draft.onFile {
                saved.append(onFile)
            }
            taken.append(draft.typedName)
        }
        update { $0.routines = saved }
    }

    /// Shows the routines a newer file holds. A routine the file did not change keeps its row,
    /// and one the user was still fixing stays as well, so nothing they typed is lost.
    func showRoutines(from file: [Routine]) {
        var waiting = routines
        let unfinished = Set(
            routines.filter { !$0.isUntouched && !$0.isComplete(taken: namesTaken(before: $0.id)) }.map(\.id))
        var shown = file.map { routine in
            guard let index = waiting.firstIndex(where: { $0.onFile == routine }) else { return RoutineDraft(routine) }
            return waiting.remove(at: index)
        }
        for var draft in waiting where unfinished.contains(draft.id) {
            draft.onFile = nil
            shown.append(draft)
        }
        routines = shown
        removedRoutine = nil
        if selectedRoutineDraft == nil {
            selectedRoutine = routines.first?.id
        }
    }
}
