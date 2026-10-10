import AppKit
import CoreAudio
import HarkCore

struct SystemToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private func schema(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
    .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map { .string($0) }),
    ])
}

private func stringProperty(_ description: String, options: [String]? = nil) -> JSONValue {
    var property: [String: JSONValue] = ["type": .string("string"), "description": .string(description)]
    if let options { property["enum"] = .array(options.map { .string($0) }) }
    return .object(property)
}

private let appProperty = stringProperty("Name of the app to open it in. Leave out for the default app.")

private func requiredString(_ key: String, in arguments: JSONValue) throws -> String {
    guard let text = arguments[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        throw SystemToolError("Missing \(key).")
    }
    return text
}

private func optionalApp(in arguments: JSONValue) -> String? {
    guard let name = arguments["app"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
        return nil
    }
    return name
}

private func displayName(ofApp name: String) -> String {
    ["vs code", "visual studio code", "vscode"].contains(name.lowercased()) ? "VS Code" : name
}

enum AppLookup {
    private static let bundleIDs = [
        "vs code": "com.microsoft.VSCode", "visual studio code": "com.microsoft.VSCode",
        "vscode": "com.microsoft.VSCode", "code": "com.microsoft.VSCode",
    ]

    @MainActor static func url(forAppNamed name: String) throws -> URL {
        let wanted = name.lowercased()
        if let id = bundleIDs[wanted], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return url
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", "\(home)/Applications"]
        for folder in folders {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            if let match = names.first(where: { $0.lowercased() == wanted + ".app" }) {
                return URL(fileURLWithPath: "\(folder)/\(match)")
            }
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.lowercased() == wanted }),
           let url = running.bundleURL {
            return url
        }
        throw SystemToolError("\(name) is not installed.")
    }

    @MainActor static func visualStudioCode() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")
    }
}

private func open(_ url: URL, in app: URL?) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    if let app {
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    } else {
        _ = try await NSWorkspace.shared.open(url, configuration: configuration)
    }
}

public struct OpenAddressTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "open_url",
            description: "Open a web address (http or https) in the default browser or a named app.",
            parameters: schema([
                "url": stringProperty("The full web address, starting with http:// or https://."),
                "app": appProperty,
            ], required: ["url"]),
            kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String {
        let address = arguments["url"]?.string ?? "the address"
        guard let app = optionalApp(in: arguments) else { return "Open \(address)" }
        return "Open \(address) in \(displayName(ofApp: app))"
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        let text = try requiredString("url", in: arguments)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil else {
            throw SystemToolError("Only http and https addresses can be opened.")
        }
        let appName = optionalApp(in: arguments)
        let app = try await MainActor.run { try appName.map(AppLookup.url(forAppNamed:)) }
        try await open(url, in: app)
        let place = appName.map { " in \(displayName(ofApp: $0))" } ?? ""
        return ToolResult(output: "Opened \(text)\(place).", summary: "Opened \(url.host() ?? text)\(place)")
    }
}

public struct OpenPathTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "open_path",
            description: "Open an existing file or folder in its default app or a named app. It never creates, moves or deletes anything.",
            parameters: schema([
                "path": stringProperty("Path of an existing file or folder. A leading ~ means the home folder."),
                "app": appProperty,
            ], required: ["path"]),
            kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String {
        let path = arguments["path"]?.string ?? "the path"
        let name = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).lastPathComponent
        guard let app = optionalApp(in: arguments) else { return "Open \(name)" }
        return "Open \(name) in \(displayName(ofApp: app))"
    }

    private static let runnableExtensions: Set<String> = [
        "command", "tool", "sh", "zsh", "bash", "fish", "scpt", "scptd", "applescript", "workflow",
        "action", "pkg", "mpkg", "terminal", "jar", "app", "shortcut", "service",
    ]

    private static func runsWhenOpened(_ path: String, isFolder: Bool) -> Bool {
        let kind = (path as NSString).pathExtension.lowercased()
        if runnableExtensions.contains(kind) { return true }
        // A file with no extension that is marked executable is a program.
        return !isFolder && kind.isEmpty && FileManager.default.isExecutableFile(atPath: path)
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        let path = (try requiredString("path", in: arguments) as NSString).expandingTildeInPath
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else {
            throw SystemToolError("\(path) does not exist.")
        }
        // Opening a script, installer or program runs it, which would be a way round the rule
        // that Hark never runs anything a model chose (decision 0008).
        guard !Self.runsWhenOpened(path, isFolder: isFolder.boolValue) else {
            throw SystemToolError("Hark does not open scripts, installers or programs.")
        }
        let appName = optionalApp(in: arguments)
        let app = try await MainActor.run { () throws -> URL? in
            if let appName { return try AppLookup.url(forAppNamed: appName) }
            return isFolder.boolValue ? AppLookup.visualStudioCode() : nil
        }
        let url = URL(fileURLWithPath: path)
        try await open(url, in: app)
        let place = app == nil ? "" : " in \(appName.map(displayName(ofApp:)) ?? "VS Code")"
        let name = url.lastPathComponent
        return ToolResult(output: "Opened \(name)\(place).", summary: "Opened \(name)\(place)")
    }
}

enum OutputVolume {
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func device() throws -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultDevice = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultDevice, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw SystemToolError("There is no sound output to control.")
        }
        return device
    }

    private static func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, as initial: T) throws -> T {
        let device = try device()
        var property = address(selector)
        guard AudioObjectHasProperty(device, &property) else {
            throw SystemToolError("This sound output cannot be controlled.")
        }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else {
            throw SystemToolError("Could not read the sound setting.")
        }
        return value
    }

    private static func write<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ newValue: T) throws {
        let device = try device()
        var property = address(selector)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &property),
              AudioObjectIsPropertySettable(device, &property, &settable) == noErr, settable.boolValue
        else { throw SystemToolError("This sound output cannot be controlled.") }
        var value = newValue
        let status = AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<T>.size), &value)
        guard status == noErr else { throw SystemToolError("Could not change the sound setting.") }
    }

    // 'vmvc': the volume the keyboard keys move, whatever the output's channel layout.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    static func percent() throws -> Int {
        Int((try read(virtualMainVolume, as: Float32(0)) * 100).rounded())
    }

    static func setPercent(_ percent: Int) throws {
        try write(virtualMainVolume, Float32(percent) / 100)
    }

    static func isMuted() throws -> Bool {
        try read(kAudioDevicePropertyMute, as: UInt32(0)) != 0
    }

    static func setMuted(_ muted: Bool) throws {
        try write(kAudioDevicePropertyMute, UInt32(muted ? 1 : 0))
    }
}

public struct SetVolumeTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "set_volume",
            description: "Set the Mac's sound volume from 0 to 100 percent.",
            parameters: schema([
                "percent": .object(["type": .string("number"), "minimum": .number(0), "maximum": .number(100),
                                    "description": .string("Volume from 0 to 100.")]),
            ], required: ["percent"]),
            kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String {
        guard let percent = arguments["percent"]?.number else { return "Set the volume" }
        return "Set the volume to \(Int(percent.rounded()))%"
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        guard let requested = arguments["percent"]?.number, (0...100).contains(requested) else {
            throw SystemToolError("The volume must be a number from 0 to 100.")
        }
        let percent = Int(requested.rounded())
        let previous = try OutputVolume.percent()
        try OutputVolume.setPercent(percent)
        return ToolResult(
            output: "Volume is now \(percent)% (was \(previous)%).",
            summary: "Set the volume to \(percent)%",
            undo: UndoStep(summary: "Put the volume back to \(previous)%") { try OutputVolume.setPercent(previous) })
    }
}

public struct SetMuteTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "set_mute",
            description: "Mute or unmute the Mac's sound.",
            parameters: schema(["muted": .object(["type": .string("boolean")])], required: ["muted"]),
            kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String {
        arguments["muted"]?.bool == false ? "Unmute the sound" : "Mute the sound"
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        guard let muted = arguments["muted"]?.bool else { throw SystemToolError("Missing muted.") }
        let previous = try OutputVolume.isMuted()
        try OutputVolume.setMuted(muted)
        return ToolResult(
            output: muted ? "Sound is muted." : "Sound is unmuted.",
            summary: muted ? "Muted the sound" : "Unmuted the sound",
            undo: UndoStep(summary: previous ? "Muted the sound again" : "Unmuted the sound") {
                try OutputVolume.setMuted(previous)
            })
    }
}

enum SystemEvents {
    /// Needs the Automation permission to control System Events (and Accessibility for keystrokes).
    @MainActor static func run(_ source: String) throws {
        var failure: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&failure)
        guard let failure else { return }
        let code = failure[NSAppleScript.errorNumber] as? Int ?? 0
        let reason = failure[NSAppleScript.errorMessage] as? String ?? "unknown error"
        throw SystemToolError("macOS refused (error \(code)): \(reason)")
    }
}

public struct SetAppearanceTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "set_appearance",
            description: "Switch the Mac between light and dark appearance.",
            parameters: schema(["mode": stringProperty("light or dark", options: ["light", "dark"])], required: ["mode"]),
            kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String {
        "Switch to \(arguments["mode"]?.string?.lowercased() ?? "the other") mode"
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        guard let mode = arguments["mode"]?.string?.lowercased(), ["light", "dark"].contains(mode) else {
            throw SystemToolError("The mode must be light or dark.")
        }
        let wasDark = Self.isDark
        try await Self.set(dark: mode == "dark")
        let previous = wasDark ? "dark" : "light"
        return ToolResult(
            output: "Appearance is now \(mode) (was \(previous)).",
            summary: "Switched to \(mode) mode",
            undo: UndoStep(summary: "Switched back to \(previous) mode") { try await Self.set(dark: wasDark) })
    }

    static var isDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    private static func set(dark: Bool) async throws {
        try await MainActor.run {
            try SystemEvents.run(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
        }
    }
}

public struct LockScreenTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(name: "lock_screen", description: "Lock the Mac's screen.",
                 parameters: schema([:], required: []), kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String { "Lock the screen" }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        try await MainActor.run {
            try SystemEvents.run(
                "tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
        }
        return ToolResult(output: "Locked the screen.", summary: "Locked the screen")
    }
}
