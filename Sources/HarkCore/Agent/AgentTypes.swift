import Foundation

/// Any JSON value: tool arguments from a model, and the schemas that describe them.
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let bool = try? value.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let array = try? value.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try value.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let bool): try value.encode(bool)
        case .number(let number): try value.encode(number)
        case .string(let string): try value.encode(string)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var string: String? {
        if case .string(let string) = self { return string }
        return nil
    }

    public var number: Double? {
        if case .number(let number) = self { return number }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let bool) = self { return bool }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }
}

/// How much care a tool needs before it runs.
public enum ToolKind: Sendable, Equatable {
    /// Reads something and changes nothing. Runs at once and its output goes back to the model.
    case lookup
    /// Changes something that is easily put back: switching, opening, hiding.
    case action
    /// Closes or quits something. Never runs until the user has said yes.
    case destructive
}

public struct ToolSpec: Sendable, Equatable {
    public let name: String
    public let description: String
    /// A JSON Schema object describing the arguments.
    public let parameters: JSONValue
    public let kind: ToolKind

    public init(name: String, description: String, parameters: JSONValue, kind: ToolKind) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.kind = kind
    }
}

public struct ToolResult: Sendable {
    /// What the model reads back: the data a lookup found, or a short confirmation.
    public let output: String
    /// One past-tense line for the user ("Opened Projects in VS Code"); nil for lookups.
    public let summary: String?
    public let undo: UndoStep?

    public init(output: String, summary: String? = nil, undo: UndoStep? = nil) {
        self.output = output
        self.summary = summary
        self.undo = undo
    }
}

/// One thing Hark can do or look up on the model's behalf.
///
/// No tool may delete, move, rename or overwrite a file, empty the trash, or run a command the
/// model wrote (decision 0008).
public protocol Tool: Sendable {
    var spec: ToolSpec { get }
    /// What a call with these arguments would do, in the present tense and plain words, for the
    /// yes-or-no question shown before a destructive call ("Quit Slack").
    func describe(_ arguments: JSONValue) -> String
    func call(_ arguments: JSONValue) async throws -> ToolResult
    /// The care this particular call needs. Most tools always answer `spec.kind`; a tool whose
    /// reach depends on its arguments (clicking a menu item named "Close Window") answers per call.
    func kind(for arguments: JSONValue) -> ToolKind
}

extension Tool {
    public func kind(for arguments: JSONValue) -> ToolKind { spec.kind }
}

public struct ToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public enum ChatMessage: Sendable, Equatable {
    case system(String)
    case user(String)
    case assistant(text: String?, calls: [ToolCall])
    case tool(callID: String, name: String, output: String)
}

public struct ChatReply: Sendable, Equatable {
    public let text: String?
    public let calls: [ToolCall]

    public init(text: String?, calls: [ToolCall]) {
        self.text = text
        self.calls = calls
    }
}

/// A chat model that can ask for tools to be called.
public protocol ChatModel: Sendable {
    func reply(to messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply
}

public enum AgentOutcome: Sendable {
    /// Everything asked for was done. `summary` is what to show the user.
    case done(summary: String, undo: [UndoStep])
    /// A destructive call is waiting for a yes. `Agent.answer(yes:)` resumes or drops it.
    case confirm(question: String)
    /// The model chose to do nothing; its own short reason.
    case nothing(String)
    case failed(String)
}
