import Foundation
import HarkCore

enum StepKind: Hashable {
    case hark, shell
}

/// One step as it is being typed. Unlike `Step` it can hold text that is not usable yet.
struct StepDraft: Identifiable, Equatable {
    static let stopAfterRange = 1...600

    let id = UUID()
    var kind = StepKind.hark
    var text = ""
    var asksFirst = false
    var stopAfter = ""
    /// Problems show only once the user has left the field, not while they are still typing in it.
    var textWasEdited = false
    var stopAfterWasEdited = false

    init() {}

    init(_ step: Step) {
        kind = step.shell == nil ? .hark : .shell
        text = step.shell ?? step.say ?? ""
        asksFirst = step.destructive
        stopAfter = step.timeout.map { Int(exactly: $0).map(String.init) ?? String($0) } ?? ""
        textWasEdited = true
        stopAfterWasEdited = true
    }

    var step: Step {
        switch kind {
        case .hark: Step(say: text.trimmed, destructive: asksFirst)
        case .shell: Step(shell: text.trimmed, destructive: asksFirst, timeout: Double(stopAfter.trimmed))
        }
    }

    var textProblem: String? {
        guard text.trimmed.isEmpty else { return nil }
        switch kind {
        case .hark: return "Type what you would say to Hark, or remove this step."
        case .shell: return "Type the command to run, or remove this step."
        }
    }

    var stopAfterProblem: String? {
        let typed = stopAfter.trimmed
        guard kind == .shell, !typed.isEmpty else { return nil }
        if let seconds = Int(typed), Self.stopAfterRange.contains(seconds) { return nil }
        return "Type a whole number of seconds from 1 to 600, or leave this empty."
    }

    func hasSameText(as other: StepDraft) -> Bool {
        kind == other.kind && text.trimmed == other.text.trimmed && asksFirst == other.asksFirst
            && stopAfter.trimmed == other.stopAfter.trimmed
    }
}

/// One routine as it is being typed.
struct RoutineDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var steps = [StepDraft()]
    var nameWasEdited = false
    /// The routine as the settings file holds it. It stays in the file as it is while what is
    /// typed here cannot be saved, so an unfinished change never removes a working routine.
    var onFile: Routine?

    init() {}

    init(_ routine: Routine) {
        name = routine.name
        steps = routine.steps.map(StepDraft.init)
        nameWasEdited = true
        onFile = routine
    }

    var typedName: String { name.trimmed }

    var routine: Routine {
        Routine(name: typedName, steps: steps.map(\.step))
    }

    var asksFirst: Bool {
        steps.contains(where: \.asksFirst)
    }

    /// True while nothing here differs from the file, so the file's own version can be kept
    /// word for word.
    var isUntouched: Bool {
        guard let onFile else { return false }
        let filed = RoutineDraft(onFile)
        return typedName == filed.typedName
            && steps.elementsEqual(filed.steps) { $0.hasSameText(as: $1) }
    }

    /// `taken` holds the names of the routines listed before this one.
    func nameProblem(taken: [String]) -> String? {
        let typed = typedName
        if typed.isEmpty {
            return "Give this routine a name, like \u{201C}pull all\u{201D}."
        }
        if taken.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) {
            return "You already have a routine called \u{201C}\(typed)\u{201D}. Choose another name."
        }
        return nil
    }

    var stepsProblem: String? {
        steps.isEmpty ? "Add a step so this routine has something to do." : nil
    }

    func isComplete(taken: [String]) -> Bool {
        nameProblem(taken: taken) == nil && stepsProblem == nil
            && steps.allSatisfy { $0.textProblem == nil && $0.stopAfterProblem == nil }
    }

    mutating func showAllProblems() {
        nameWasEdited = true
        for index in steps.indices {
            steps[index].textWasEdited = true
            steps[index].stopAfterWasEdited = true
        }
    }
}

/// A routine that was just removed and can still be put back.
struct RemovedRoutine: Equatable {
    let draft: RoutineDraft
    let index: Int
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
