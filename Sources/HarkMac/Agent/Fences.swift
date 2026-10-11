import Foundation
import HarkCore
import Synchronization

/// A tool behind a check that runs before every call, whatever the model asked for.
struct Fenced: Tool {
    let tool: any Tool
    let check: @Sendable (JSONValue) throws -> Void

    var spec: ToolSpec { tool.spec }

    func describe(_ arguments: JSONValue) -> String { tool.describe(arguments) }

    func kind(for arguments: JSONValue) -> ToolKind { tool.kind(for: arguments) }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        try check(arguments)
        return try await tool.call(arguments)
    }
}

struct FenceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The fences one command's tools share (see SAFETY.md).
final class Fences: Sendable {
    private let heard: String
    private let openAddresses: [String]
    private let fileName: @Sendable (String) -> String?
    private let actions = Mutex(0)

    /// `fileName` answers with the name of the file or folder an id stands for, or nil for an id
    /// that is not a file.
    init(heard: String, openAddresses: [String], fileName: @escaping @Sendable (String) -> String?) {
        self.heard = heard
        self.openAddresses = openAddresses
        self.fileName = fileName
    }

    /// Wraps each tool in the checks that apply to it.
    func around(_ tools: [any Tool]) -> [any Tool] {
        tools.map { tool in
            Fenced(tool: tool) { [self] arguments in
                if tool.spec.kind != .lookup { try countAction() }
                try refuseSelf(arguments["app"]?.string ?? arguments["name"]?.string, for: tool.spec.name)
                switch tool.spec.name {
                case "open_url": try allow(address: arguments["url"]?.string)
                case "new_tab": try allow(address: arguments["address"]?.string.flatMap { webAddress(for: $0)?.absoluteString })
                case "click_menu", "list_menu": try refuseTerminal(arguments["app"]?.string)
                case "set_field": try allow(typing: arguments["text"]?.string)
                case "open_path":
                    try allow(file: (arguments["path"]?.string).map { URL(fileURLWithPath: $0).lastPathComponent })
                case "open_item":
                    for id in (arguments["ids"]?.array ?? []).compactMap(\.string) { try allow(file: fileName(id)) }
                default: break
                }
            }
        }
    }

    private func countAction() throws {
        let count = actions.withLock { count in
            count += 1
            return count
        }
        guard count <= Safety.mostActionsPerCommand else {
            throw FenceError(message: "That is more actions than one command may take.")
        }
    }

    private func allow(address: String?) throws {
        // No address means a blank tab, which carries nothing anywhere.
        guard let address, !address.isEmpty else { return }
        guard let url = URL(string: address),
              Safety.addressIsTraceable(url, toHeard: heard, openAddresses: openAddresses)
        else { throw FenceError(message: "Hark only opens an address the user named.") }
    }

    /// Hark only types the user's own words. A model that could type anything could be talked
    /// into typing what it read somewhere else.
    private func allow(typing text: String?) throws {
        guard let text, Safety.usesOnlyWords(said: heard, in: text) else {
            throw FenceError(message: "Hark only types words the user said.")
        }
    }

    private func allow(file name: String?) throws {
        guard let name, !Safety.fileWasAskedFor(name, heard: heard) else { return }
        throw FenceError(message: "The user did not ask for \(name). Do not open a file they did not name; look for an app, window or tab with that name instead.")
    }

    /// Hark's own menu has "Quit Hark" in it, and its windows have close buttons. The model is
    /// kept away from all of it: only the user quits Hark.
    private func refuseSelf(_ app: String?, for tool: String) throws {
        guard tool != "open_app", app?.trimmingCharacters(in: .whitespaces).lowercased() == "hark" else { return }
        throw FenceError(message: "Hark does not act on itself.")
    }

    /// A terminal's menus can run things, so the model gets no way into one.
    private func refuseTerminal(_ app: String?) throws {
        let name = (app ?? "").lowercased()
        guard !AppNames.isTerminal(named: name) else {
            throw FenceError(message: "Hark does not use a terminal's menus.")
        }
    }
}
