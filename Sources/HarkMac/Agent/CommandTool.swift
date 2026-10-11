import Foundation
import HarkCore

/// Runs one terminal command the model wrote, for tasks that only the terminal can do ("which process is using port
/// 3000", "what changed in this repo"). It is the one place a model's own text reaches a shell, so it is fenced three
/// ways: the exact command is shown and nothing runs until the user says yes; macOS limits what it can touch
/// (`CommandSandbox`: no deleting, moving or renaming, and without the user's second switch no writing and no network);
/// and what it prints goes to the user only, never back to a model.
struct RunCommandTool: Tool {
    /// Whether the user has allowed commands that change files and use the network.
    let allowingChanges: Bool

    private static let longest = 600
    private static let timeout: Double = 20

    var spec: ToolSpec {
        ToolSpec(
            name: "run_command",
            description: "Run one terminal command on this Mac when the task needs the terminal and no other tool does it "
                + "(git status, lsof, ps, ls, du, brew list and the like). The user is shown the exact command and must say "
                + "yes first. It cannot delete, move or rename anything"
                + (allowingChanges ? "." : ", write files or use the network, so use it to look things up.")
                + " Its output is shown to the user and is not returned to you.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object(["command": .object(["type": .string("string")])]),
                "required": .array([.string("command")]),
            ]),
            kind: .destructive)
    }

    func describe(_ arguments: JSONValue) -> String {
        "Run in the terminal: \(arguments["command"]?.string ?? "")"
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        let text = (arguments["command"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ItemToolError(message: "There was no command to run.") }
        guard text.count <= Self.longest else { throw ItemToolError(message: "That command is too long to run.") }
        let finished = try await RoutineRunner.launch(
            ShellCommand(text: text, environment: [:], label: nil), timeout: .seconds(Self.timeout), sandbox: allowingChanges)
        if finished.timedOut { throw ItemToolError(message: "It took longer than \(Int(Self.timeout)) seconds, so it was stopped.") }
        let shown = Self.lastLines(of: finished.output, count: 3)
        guard finished.status == 0 else {
            let why = shown.isEmpty ? "it failed with code \(finished.status)" : shown
            return ToolResult(output: "The command failed with code \(finished.status).", summary: "Ran it, but \(why)")
        }
        return ToolResult(output: "The command finished.", summary: shown.isEmpty ? "Ran it" : shown)
    }

    /// The last few non-empty lines, joined, for the overlay.
    static func lastLines(of output: String, count: Int) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(count).joined(separator: " · ")
    }
}
