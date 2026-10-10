import Foundation
import HarkCore

/// Lets the model pick one of the user's routines by name. It chooses which routine and may pass
/// on words the user said; the steps are the user's own and the model never sees or writes them.
struct RoutineTool: Tool {
    typealias Run = @Sendable (RoutineCall) async -> Outcome

    let spec = ToolSpec(
        name: "run_routine",
        description: "Run one of the routines the user set up, by its name exactly as listed. Put a port, number or name the user said in argument when the routine takes one.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")]),
                "argument": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("name")]),
        ]),
        kind: .destructive)

    let routines: [Routine]
    let repos: [String]
    /// What the user said, which is all an argument may be made of.
    let said: String
    let run: Run

    /// A model picking the wrong routine must cost a keypress, not a side effect, so every call
    /// that names a real routine asks first. One that names none has nothing to ask about and
    /// goes straight back to the model as an error.
    func kind(for arguments: JSONValue) -> ToolKind {
        (try? chosen(by: arguments)) == nil ? .lookup : .destructive
    }

    func describe(_ arguments: JSONValue) -> String {
        guard let call = try? chosen(by: arguments) else {
            return "Run the routine \(arguments["name"]?.string ?? "")"
        }
        return Routines.describe(call, everyStep: true, repos: repos)
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        let outcome = await run(try chosen(by: arguments))
        guard case .done(let line) = outcome else { throw ItemToolError(message: outcome.shown) }
        return ToolResult(output: line, summary: line)
    }

    private func chosen(by arguments: JSONValue) throws -> RoutineCall {
        let call = try Routines.chosen(
            name: arguments["name"]?.string ?? "", argument: arguments["argument"]?.string, said: said,
            among: routines)
        try Routines.check(call, repos: repos)
        return call
    }
}
