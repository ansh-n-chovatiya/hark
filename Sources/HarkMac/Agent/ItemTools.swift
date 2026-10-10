import AppKit
import Foundation
import HarkCore
import Synchronization

/// What is open right now, under short ids the model can refer to ("a2", "t7").
final class Desk: Sendable {
    private struct State {
        var items: [String: Item] = [:]
        var counts: [ItemKind: Int] = [:]
    }

    private let state = Mutex(State())

    /// Gives each item an id and returns one line per item for the model to read.
    /// `inFront` holds the ids of the items the user is looking at, which get a note so that
    /// "this window" and "that tab" mean something to the model.
    func add(_ items: [Item], inFront: Set<String> = []) -> [String] {
        state.withLock { state in
            items.map { item in
                let number = (state.counts[item.kind] ?? 0) + 1
                state.counts[item.kind] = number
                let id = "\(Self.letter(for: item.kind))\(number)"
                state.items[id] = item
                let parts = [String(item.title.prefix(80)), item.detail, item.owner].filter { !$0.isEmpty }
                let note = inFront.contains(item.id) ? " (in front)" : ""
                return "\(id) \(item.kind.rawValue): \(parts.joined(separator: " | "))\(note)"
            }
        }
    }

    /// Models sometimes answer with a thing's name where an id was asked for, so a name that
    /// matches exactly one item is accepted too.
    func item(_ reference: String) -> Item? {
        state.withLock { state in
            if let item = state.items[reference.lowercased()] { return item }
            let named = state.items.values.filter { $0.title.caseInsensitiveCompare(reference) == .orderedSame }
            return named.count == 1 ? named[0] : nil
        }
    }

    private static func letter(for kind: ItemKind) -> String {
        switch kind {
        case .app: "a"
        case .window: "w"
        case .tab: "t"
        case .file: "f"
        case .clip: "c"
        case .workspace: "s"
        case .routine: "r"
        }
    }
}

struct ItemToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Brings forward, hides, closes or quits items the model names by id.
struct ItemActionTool: Tool {
    typealias Perform = @Sendable (Verb, Item) async throws -> UndoStep?

    let spec: ToolSpec
    private let verb: Verb
    private let wording: (present: String, past: String)
    private let allowed: Set<ItemKind>
    private let desk: Desk
    private let perform: Perform

    static func all(desk: Desk, perform: @escaping Perform) -> [any Tool] {
        [
            ItemActionTool(
                name: "open_item", verb: .open, kind: .action, wording: ("Open", "Opened"),
                about: "Bring apps, windows or browser tabs to the front, or open files and folders, by id.",
                allowed: [.app, .window, .tab, .file], desk: desk, perform: perform),
            ItemActionTool(
                name: "hide_item", verb: .hide, kind: .action, wording: ("Hide", "Hid"),
                about: "Hide apps by id.", allowed: [.app, .window], desk: desk, perform: perform),
            ItemActionTool(
                name: "close_item", verb: .close, kind: .destructive, wording: ("Close", "Closed"),
                about: "Close windows or browser tabs by id. To get rid of a whole app use quit_app.",
                allowed: [.window, .tab], desk: desk, perform: perform),
            ItemActionTool(
                name: "quit_app", verb: .quit, kind: .destructive, wording: ("Quit", "Quit"),
                about: "Quit running apps by id.", allowed: [.app], desk: desk, perform: perform),
        ]
    }

    private init(
        name: String, verb: Verb, kind: ToolKind, wording: (present: String, past: String), about: String,
        allowed: Set<ItemKind>, desk: Desk, perform: @escaping Perform
    ) {
        spec = ToolSpec(
            name: name, description: about,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "ids": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
                ]),
                "required": .array([.string("ids")]),
            ]),
            kind: kind)
        self.verb = verb
        self.wording = wording
        self.allowed = allowed
        self.desk = desk
        self.perform = perform
    }

    func describe(_ arguments: JSONValue) -> String {
        // An id that matches nothing is shown as given, so the question never reads "Quit ?".
        let names = references(in: arguments).map { desk.item($0)?.title ?? $0 }
        return "\(wording.present) \(Self.listed(names))"
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        let ids = references(in: arguments)
        guard !ids.isEmpty else { throw ItemToolError(message: "No ids were given.") }
        var undo: [UndoStep] = []
        var done: [String] = []
        for id in ids {
            guard let item = desk.item(id) else { throw ItemToolError(message: "There is no item \(id).") }
            guard allowed.contains(item.kind) else {
                throw ItemToolError(message: "\(spec.name) does not work on a \(item.kind.rawValue) (\(id)).")
            }
            if let step = try await perform(verb, item) { undo.append(step) }
            done.append(item.title)
        }
        let summary = "\(wording.past) \(Self.listed(done))"
        let steps = Array(undo.reversed())
        let together = steps.isEmpty ? nil : UndoStep(summary: "Undid: \(summary)") {
            for step in steps { try await step.run() }
        }
        return ToolResult(output: summary, summary: summary, undo: together)
    }

    private func references(in arguments: JSONValue) -> [String] {
        (arguments["ids"]?.array ?? []).compactMap(\.string)
    }

    /// Everything is named before a yes or no, so the user sees exactly what is at stake.
    private static func listed(_ names: [String]) -> String {
        names.count <= 8 ? names.joined(separator: ", ") : names.prefix(7).joined(separator: ", ") + " and \(names.count - 7) more"
    }
}

/// Searches the user's folders by name. What it finds gets ids the other tools accept.
struct FindFilesTool: Tool {
    typealias Search = @Sendable (String) async -> [Item]

    private static let most = 8

    let spec = ToolSpec(
        name: "find_files",
        description: "Find files and folders in the user's folders by words from their names. Returns ids to use with open_item.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "folders_only": .object(["type": .string("boolean")]),
            ]),
            "required": .array([.string("query")]),
        ]),
        kind: .lookup)

    let desk: Desk
    let search: Search

    func describe(_ arguments: JSONValue) -> String {
        "Look for files named \(arguments["query"]?.string ?? "")"
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        guard let query = arguments["query"]?.string, !query.isEmpty else {
            throw ItemToolError(message: "No query was given.")
        }
        var found = await search(query)
        if arguments["folders_only"]?.bool == true {
            found.removeAll { !FindFilesTool.isFolder($0) }
        }
        let lines = desk.add(Array(found.prefix(Self.most)))
        return ToolResult(output: lines.isEmpty ? "Nothing found." : lines.joined(separator: "\n"))
    }

    static func isFolder(_ item: Item) -> Bool {
        // A source may say so itself; an evaluation's made-up files exist only as names.
        if let stated = item.payload["folder"] { return stated == "yes" }
        var isDirectory: ObjCBool = false
        guard let path = item.payload["path"] else { return false }
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

struct NewTabTool: Tool {
    let spec = ToolSpec(
        name: "new_tab",
        description: "Open a new browser tab. Give a site or search words in address, or leave it out for a blank tab.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object(["address": .object(["type": .string("string")])]),
        ]),
        kind: .action)

    func describe(_ arguments: JSONValue) -> String {
        guard let address = webAddress(for: arguments["address"]?.string ?? "") else { return "Open a new tab" }
        return "Open \(address.host() ?? address.absoluteString) in a new tab"
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        let address = webAddress(for: arguments["address"]?.string ?? "")
        try await Browser.openNewTab(address)
        let summary = address.map { "Opened \($0.host() ?? $0.absoluteString) in a new tab" } ?? "Opened a new tab"
        return ToolResult(output: summary, summary: summary)
    }
}

/// Starts or brings forward an app by name, including one that is not running and so has no id.
struct OpenAppTool: Tool {
    /// Returns the app's real name once it is open.
    typealias Launch = @Sendable (String) async throws -> String

    let spec = ToolSpec(
        name: "open_app",
        description: "Open an installed app by name, whether or not it is running. Use open_item for apps that have an id.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object(["name": .object(["type": .string("string")])]),
            "required": .array([.string("name")]),
        ]),
        kind: .action)

    let launch: Launch

    func describe(_ arguments: JSONValue) -> String {
        "Open \(arguments["name"]?.string ?? "an app")"
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        guard let name = arguments["name"]?.string, !name.isEmpty else {
            throw ItemToolError(message: "No app name was given.")
        }
        let opened = try await launch(name)
        return ToolResult(output: "Opened \(opened)", summary: "Opened \(opened)")
    }
}

/// Opens a web page the user saved under a name.
struct OpenLinkTool: Tool {
    let spec = ToolSpec(
        name: "open_link",
        description: "Open one of the user's saved links by its name.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object(["name": .object(["type": .string("string")])]),
            "required": .array([.string("name")]),
        ]),
        kind: .action)

    let links: [String: String]

    func describe(_ arguments: JSONValue) -> String {
        "Open \(arguments["name"]?.string ?? "a saved link")"
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        guard let link = Links.find(arguments["name"]?.string ?? "", in: links) else {
            throw ItemToolError(message: "There is no saved link with that name.")
        }
        try await Browser.openNewTab(link.address)
        return ToolResult(output: "Opened \(link.name)", summary: "Opened \(link.name)")
    }
}

/// Puts a listed item's address, name or path on the clipboard, for "copy this tab's address".
struct CopyFromItemTool: Tool {
    let spec = ToolSpec(
        name: "copy_from_item",
        description: "Copy something about a listed item to the clipboard: its web address (tabs), its name, or its path (files and folders).",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "what": .object(["type": .string("string"), "enum": .array([.string("address"), .string("name"), .string("path")])]),
            ]),
            "required": .array([.string("id"), .string("what")]),
        ]),
        kind: .action)

    let desk: Desk

    func describe(_ arguments: JSONValue) -> String {
        let id = arguments["id"]?.string ?? ""
        return "Copy the \(arguments["what"]?.string ?? "name") of \(desk.item(id)?.title ?? id)"
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        guard let item = desk.item(arguments["id"]?.string ?? "") else {
            throw ItemToolError(message: "There is no item with that id.")
        }
        let what = arguments["what"]?.string ?? "name"
        let value: String? = switch what {
        case "address": item.payload["url"]
        case "path": item.payload["path"]
        default: item.title
        }
        guard let value, !value.isEmpty else {
            throw ItemToolError(message: "\(item.title) has no \(what) to copy.")
        }
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
        let summary = "Copied the \(what) of \(item.title)"
        return ToolResult(output: summary, summary: summary)
    }
}
