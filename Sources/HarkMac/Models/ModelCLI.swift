import Foundation
import os

/// An AI command-line tool found on this Mac that Hark can use as a model.
public struct ModelCLI: Sendable, Equatable {
    public let name: String
    public let label: String
    public let path: String
}

public enum ModelCLIs {
    /// Tools Hark knows how to talk to, best first. Only Claude Code has been tried so far.
    private static let known: [(name: String, label: String)] = [("claude", "Claude Code")]

    private static let folders = [
        "~/.local/bin", "~/.claude/local", "~/.npm-global/bin", "~/.bun/bin", "~/.volta/bin",
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
    ]

    private static let cache = OSAllocatedUnfairLock<[ModelCLI]?>(initialState: nil)

    /// What the last `discover()` found. Empty until it has run.
    public static var found: [ModelCLI] { cache.withLock { $0 } ?? [] }

    /// For the settings previews, which have no tool installed to find.
    static func setFound(_ tools: [ModelCLI]) {
        cache.withLock { $0 = tools }
    }

    /// Looks in the usual install folders, then asks a login shell, which knows the user's own PATH. Run
    /// it once when Hark starts, away from the main thread.
    @discardableResult
    public static func discover() -> [ModelCLI] {
        let result = known.compactMap { tool -> ModelCLI? in
            guard let path = inFolders(tool.name) ?? inLoginShell(tool.name) else { return nil }
            return ModelCLI(name: tool.name, label: tool.label, path: path)
        }
        cache.withLock { $0 = result }
        return result
    }

    private static func inFolders(_ name: String) -> String? {
        for folder in folders {
            let path = NSString(string: folder).expandingTildeInPath + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private static func inLoginShell(_ name: String) -> String? {
        // The output goes to a file, not a pipe: a login script that leaves a program running (an ssh agent, say)
        // would keep a pipe open and the read would never end.
        let file = FileManager.default.temporaryDirectory.appending(path: "hark-which-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: file.path, contents: nil),
              let sink = try? FileHandle(forWritingTo: file) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(name)"]
        process.standardOutput = sink
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        try? sink.close()
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let path = text.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}

struct CLIModelError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Runs one program with the prompt on standard input. The arguments are an array, never a shell line,
/// and it is stopped when it takes too long or when the request is cancelled (the model that lost a
/// race).
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

enum CLIProcess {
    private static let outputLimit = 400_000

    static func run(
        _ path: String, arguments: [String], input: String, timeout: TimeInterval, folder: URL
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        // A program started from an app has a short PATH; tools like this are often scripts that need node.
        let extra = ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].map { NSString(string: $0).expandingTildeInPath }
        environment["PATH"] = (extra + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe()
        // Errors go to a file, read only if the program fails: a pipe nobody reads would stall a chatty program.
        let errorFile = FileManager.default.temporaryDirectory.appending(path: "hark-cli-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)
        let stderr = try? FileHandle(forWritingTo: errorFile)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr ?? FileHandle.nullDevice
        let cancelled = CancelFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        try? stderr?.close()
                        try? FileManager.default.removeItem(at: errorFile)
                    }
                    guard !cancelled.isSet else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: CLIModelError(message: "The tool could not be started: \(error.localizedDescription)"))
                        return
                    }
                    // Cancelled while it was starting: stop it now, as the cancel handler found nothing running.
                    if cancelled.isSet { process.terminate() }
                    // A program that has already stopped would make this write fail; that is its answer, below.
                    try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                    try? stdin.fileHandleForWriting.close()
                    let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                    // Read before waiting: a full pipe would otherwise stop the program from finishing.
                    let data = stdout.fileHandleForReading.readData(ofLength: outputLimit)
                    process.waitUntilExit()
                    timer.cancel()
                    let text = String(decoding: data, as: UTF8.self)
                    if cancelled.isSet {
                        continuation.resume(throwing: CancellationError())
                    } else if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CLIModelError(message: "The tool did not answer in time"))
                    } else if process.terminationStatus != 0, text.isEmpty {
                        let error = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
                        let line = error.split(whereSeparator: \.isNewline).first.map(String.init) ?? "it failed"
                        continuation.resume(throwing: CLIModelError(message: "The tool stopped: \(line.prefix(160))"))
                    } else {
                        continuation.resume(returning: text)
                    }
                }
            }
        } onCancel: {
            cancelled.set()
            if process.isRunning { process.terminate() }
        }
    }
}
