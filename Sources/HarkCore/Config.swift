import Foundation

public struct Step: Codable, Sendable, Equatable {
    public var say: String?
    public var shell: String?
    public var destructive: Bool
    /// Seconds a shell step may take before it is stopped. Left out, it is 30.
    public var timeout: Double?

    public init(say: String? = nil, shell: String? = nil, destructive: Bool = false, timeout: Double? = nil) {
        self.say = say
        self.shell = shell
        self.destructive = destructive
        self.timeout = timeout
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        say = try values.decodeIfPresent(String.self, forKey: .say)
        shell = try values.decodeIfPresent(String.self, forKey: .shell)
        destructive = try values.decodeIfPresent(Bool.self, forKey: .destructive) ?? false
        timeout = try values.decodeIfPresent(Double.self, forKey: .timeout)
    }
}

public struct Routine: Codable, Sendable, Equatable {
    public var name: String
    public var steps: [Step]

    public init(name: String, steps: [Step]) {
        self.name = name
        self.steps = steps
    }
}

public struct Config: Codable, Sendable, Equatable {
    public var hotkey: String
    /// The key tapped to type a command. Empty turns typing by key off.
    public var typeKey: String
    public var searchFolders: [String]
    public var repos: [String]
    public var aliases: [String: String]
    public var routines: [Routine]
    /// Web pages by name: what the user calls it, and its address.
    public var links: [String: String]
    public var clipLimit: Int
    /// A model that works out what was meant when the built-in rules are unsure. It is reached
    /// through an OpenAI-compatible chat endpoint: Ollama on this Mac by default, or a hosted one
    /// such as Gemini when `modelKey` is set.
    public var useModel: Bool
    public var model: String
    public var modelURL: String
    public var modelKey: String
    /// A model on this Mac that answers when the hosted one is slow or unreachable. Empty turns it off.
    public var fallbackModel: String
    public var fallbackModelURL: String

    public init(
        hotkey: String = "rightOption",
        typeKey: String = "rightCommand",
        searchFolders: [String] = [],
        repos: [String] = [],
        aliases: [String: String] = [:],
        routines: [Routine] = [],
        links: [String: String] = [:],
        clipLimit: Int = 5000,
        useModel: Bool = true,
        model: String = "qwen2.5:3b",
        modelURL: String = "http://127.0.0.1:11434/v1",
        modelKey: String = "",
        fallbackModel: String = "qwen2.5:3b",
        fallbackModelURL: String = "http://127.0.0.1:11434/v1"
    ) {
        self.hotkey = hotkey
        self.typeKey = typeKey
        self.searchFolders = searchFolders
        self.repos = repos
        self.aliases = aliases
        self.routines = routines
        self.links = links
        self.clipLimit = clipLimit
        self.useModel = useModel
        self.model = model
        self.modelURL = modelURL
        self.modelKey = modelKey
        self.fallbackModel = fallbackModel
        self.fallbackModelURL = fallbackModelURL
    }

    // A hand-edited file may leave fields out; each missing one takes its default.
    public init(from decoder: Decoder) throws {
        let defaults = Config()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try values.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey
        typeKey = try values.decodeIfPresent(String.self, forKey: .typeKey) ?? defaults.typeKey
        searchFolders = try values.decodeIfPresent([String].self, forKey: .searchFolders) ?? defaults.searchFolders
        repos = try values.decodeIfPresent([String].self, forKey: .repos) ?? defaults.repos
        aliases = try values.decodeIfPresent([String: String].self, forKey: .aliases) ?? defaults.aliases
        routines = try values.decodeIfPresent([Routine].self, forKey: .routines) ?? defaults.routines
        links = try values.decodeIfPresent([String: String].self, forKey: .links) ?? defaults.links
        clipLimit = try values.decodeIfPresent(Int.self, forKey: .clipLimit) ?? defaults.clipLimit
        useModel = try values.decodeIfPresent(Bool.self, forKey: .useModel) ?? defaults.useModel
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        modelURL = try values.decodeIfPresent(String.self, forKey: .modelURL) ?? defaults.modelURL
        modelKey = try values.decodeIfPresent(String.self, forKey: .modelKey) ?? defaults.modelKey
        fallbackModel = try values.decodeIfPresent(String.self, forKey: .fallbackModel) ?? defaults.fallbackModel
        fallbackModelURL = try values.decodeIfPresent(String.self, forKey: .fallbackModelURL) ?? defaults.fallbackModelURL
    }

    public static func load(from url: URL) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
        // The file can hold a model key, so only this user may read it.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum Paths {
    public static var config: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/hark/config.json")
    }

    public static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Hark")
    }

    public static var timings: URL { support.appending(path: "timings.jsonl") }
    public static var wrong: URL { support.appending(path: "wrong.jsonl") }
}
