import Foundation

/// A routine the user asked for, with the words said after its name.
public struct RoutineCall: Sendable, Equatable {
    public let routine: Routine
    public let argument: String?

    public init(routine: Routine, argument: String? = nil) {
        self.routine = routine
        self.argument = argument
    }
}

/// One shell command ready to run. What was said and the folder travel in the environment and
/// the text only refers to them, so neither is ever read as part of the command.
public struct ShellCommand: Sendable, Equatable {
    public let text: String
    public let environment: [String: String]
    /// The folder's name, when the step repeats for each project.
    public let label: String?

    public init(text: String, environment: [String: String], label: String?) {
        self.text = text
        self.environment = environment
        self.label = label
    }
}

public struct RoutineError: LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

/// Routines are lists of steps the user wrote in their settings. A model may pick which one to
/// run and pass on words the user said; it never writes a step (decision 0008).
public enum Routines {
    private static let startWords: Set<String> = ["run", "start", "launch", "begin", "do"]
    private static let wholeWords: Set<String> = ["entire", "whole", "full"]
    public static let mostNesting = 3
    public static let defaultTimeout: Double = 30

    static let argumentMark = "{arg}"
    static let repoMark = "{repo}"
    static let argumentVariable = "HARK_ARG"
    static let repoVariable = "HARK_REPO"

    private static let longestLine = 120

    /// The routine a command names outright, with or without "run" in front. Words after the
    /// name are its argument, and only a routine that uses one may have words after its name, so
    /// "pull all the tabs together" is not taken for a routine called "pull all".
    public static func find(in transcript: String, among routines: [Routine]) -> RoutineCall? {
        let words = commandWords(heardWords(transcript))
        // "Run the entire morning setup" names the routine "morning setup": a word for starting
        // it and a word for all of it add nothing. The words as said are tried first, so a routine
        // really called "start local" still wins.
        var plain = words
        if let first = plain.first, startWords.contains(first) { plain.removeFirst() }
        plain.removeAll(where: wholeWords.contains)
        let readings = plain == words ? [words] : [words, plain]
        let named = routines
            .map { (routine: $0, name: nameWords($0.name)) }
            .filter { !$0.name.isEmpty }
            .sorted { $0.name.count > $1.name.count }
        for reading in readings {
            for (routine, name) in named where reading.starts(with: name) {
                let rest = reading.dropFirst(name.count)
                if rest.isEmpty { return RoutineCall(routine: routine) }
                if takesArgument(routine) { return RoutineCall(routine: routine, argument: rest.joined(separator: " ")) }
            }
        }
        return nil
    }

    /// The routine a model picked. Its name must be one of the user's, and its argument may only
    /// carry words the user said, so a model cannot pass on something it read elsewhere.
    public static func chosen(
        name: String, argument: String?, said: String, among routines: [Routine]
    ) throws -> RoutineCall {
        let wanted = nameWords(name)
        guard !wanted.isEmpty, let routine = routines.first(where: { nameWords($0.name) == wanted }) else {
            throw RoutineError("There is no routine called \(name).")
        }
        let words = normalizedWords(argument ?? "")
        guard let argument, !words.isEmpty else { return RoutineCall(routine: routine) }
        guard Safety.usesOnlyWords(said: said, in: argument) else {
            throw RoutineError("Hark only passes on words the user said.")
        }
        return RoutineCall(routine: routine, argument: words.joined(separator: " "))
    }

    /// Throws, in words for the user, when the routine cannot be run as asked.
    public static func check(_ call: RoutineCall, repos: [String]) throws {
        let name = quoted(call.routine.name)
        let steps = call.routine.steps
        guard !steps.isEmpty else { throw RoutineError("\(name) has no steps yet") }
        if let broken = steps.firstIndex(where: { ($0.say == nil) == ($0.shell == nil) }) {
            throw RoutineError("Step \(broken + 1) of \(name) needs either \"say\" or \"shell\", and only one of them")
        }
        if takesArgument(call.routine), call.argument == nil {
            throw RoutineError("\(name) needs something said after its name")
        }
        if repos.isEmpty, shellSteps(of: call.routine).contains(where: { $0.contains(repoMark) }) {
            throw RoutineError("\(name) runs once for each project, and your settings list no projects")
        }
    }

    public static func needsYes(_ call: RoutineCall) -> Bool {
        call.routine.steps.contains(where: \.destructive)
    }

    /// What running the routine means, for the yes-or-no question: its name and the commands at
    /// stake, word for word. With `everyStep` false only the steps marked destructive are quoted.
    public static func describe(_ call: RoutineCall, everyStep: Bool, repos: [String]) -> String {
        let steps = call.routine.steps.filter { everyStep || $0.destructive }
        let quotes = steps.map { step -> String in
            guard let shell = step.shell else { return "say \(quoted(step.say ?? ""))" }
            let text = filled(shell, argument: call.argument)
            return shell.contains(repoMark) ? "\(text), once for each of \(repos.count) projects" : text
        }
        return "Run \(quoted(call.routine.name))" + (quotes.isEmpty ? "" : " (\(quotes.joined(separator: "; ")))")
    }

    /// What a dry run reports in place of running anything.
    public static func dryRunText(for call: RoutineCall, repos: [String]) -> String {
        let commands = call.routine.steps.flatMap { step -> [String] in
            guard let shell = step.shell else { return ["say \(quoted(step.say ?? ""))"] }
            let text = filled(shell, argument: call.argument)
            return shell.contains(repoMark) ? repos.map { text.replacingOccurrences(of: repoMark, with: $0) } : [text]
        }
        return "Would run \(call.routine.name): \(commands.joined(separator: "; "))"
    }

    /// The commands one shell step becomes: one, or one for each project when it uses `{repo}`.
    public static func commands(for shell: String, argument: String?, repos: [String]) -> [ShellCommand] {
        var text = shell
        var environment: [String: String] = [:]
        if shell.contains(argumentMark) {
            text = text.replacingOccurrences(of: argumentMark, with: reference(to: argumentVariable))
            environment[argumentVariable] = argument ?? ""
        }
        guard shell.contains(repoMark) else { return [ShellCommand(text: text, environment: environment, label: nil)] }
        text = text.replacingOccurrences(of: repoMark, with: reference(to: repoVariable))
        return repos.map { repo in
            let path = NSString(string: repo).expandingTildeInPath
            return ShellCommand(
                text: text, environment: environment.merging([repoVariable: path]) { _, folder in folder },
                label: URL(fileURLWithPath: path).lastPathComponent)
        }
    }

    /// The last line of a command's output that says anything, cut to fit the overlay.
    public static func lastLine(of output: String) -> String {
        let line = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
        return line.count > longestLine ? line.prefix(longestLine - 1) + "…" : line
    }

    /// One step's line for the user: the command's own last line, or one short part for each project.
    public static func line(for outputs: [(label: String?, line: String)]) -> String {
        outputs.map { output in
            guard let label = output.label else { return output.line }
            return "\(label) \(output.line.isEmpty ? "done" : output.line)"
        }.joined(separator: ", ")
    }

    public static func result(name: String, line: String?) -> String {
        guard let line, !line.isEmpty else { return "Ran \(name)" }
        return "\(name): \(line)"
    }

    public static func stopped(name: String, step: Int, because reason: String) -> String {
        "\(quoted(name)) stopped at step \(step): \(reason)"
    }

    private static func takesArgument(_ routine: Routine) -> Bool {
        shellSteps(of: routine).contains { $0.contains(argumentMark) }
    }

    private static func shellSteps(of routine: Routine) -> [String] {
        routine.steps.compactMap(\.shell)
    }

    private static func nameWords(_ name: String) -> [String] {
        commandWords(heardWords(name))
    }

    private static func filled(_ shell: String, argument: String?) -> String {
        guard let argument else { return shell }
        return shell.replacingOccurrences(of: argumentMark, with: argument)
    }

    private static func reference(to variable: String) -> String {
        "\"$\(variable)\""
    }

    private static func quoted(_ text: String) -> String {
        "\u{201C}\(text)\u{201D}"
    }
}
