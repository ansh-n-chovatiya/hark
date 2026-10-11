import Foundation
import HarkCore

/// Runs the shell steps of a routine. Every command here is text the user wrote in their
/// settings; nothing a model wrote reaches a shell (decision 0008).
enum RoutineRunner {
    struct Finished: Sendable {
        let status: Int32
        let timedOut: Bool
        let output: String
    }

    /// A program that ignores the request to stop is ended outright after this long.
    private static let grace: Duration = .seconds(2)
    /// Only the last line is shown, so only the end of long output is read back.
    private static let mostOutputRead: UInt64 = 16_384

    /// Runs one shell step, once or once for each project, and returns its line for the user.
    /// Throws a `RoutineError` saying why as soon as a command fails or takes too long.
    static func run(_ shell: String, timeout: Double, argument: String?, repos: [String], here: String? = nil) async throws -> String {
        var outputs: [(label: String?, line: String)] = []
        for command in Routines.commands(for: shell, argument: argument, repos: repos, here: here) {
            let place = command.label.map { "in \($0), " } ?? ""
            let finished = try await launch(command, timeout: .seconds(timeout))
            let line = Routines.lastLine(of: finished.output)
            if finished.timedOut {
                throw RoutineError("\(place)it took longer than \(timeout == 1 ? "1 second" : "\(timeout.formatted()) seconds")")
            }
            guard finished.status == 0 else {
                throw RoutineError(place + (line.isEmpty ? "the command failed with code \(finished.status)" : line))
            }
            outputs.append((command.label, line))
        }
        return Routines.line(for: outputs)
    }

    /// `sandbox` nil runs the command as written (a routine). Otherwise it runs under `CommandSandbox`, with the value
    /// saying whether changes to files are allowed.
    static func launch(_ command: ShellCommand, timeout: Duration, sandbox: Bool? = nil) async throws -> Finished {
        // Output goes to a file, not a pipe: a pipe stays open for as long as anything the
        // command started is still running, and reading it would wait for that too.
        let capture = FileManager.default.temporaryDirectory.appending(path: "hark-step-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: capture.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: capture) }
        let writer = try FileHandle(forWritingTo: capture)
        defer { try? writer.close() }

        let process = Process()
        if let sandbox {
            let wrapped = CommandSandbox.arguments(running: command.text, allowingChanges: sandbox)
            process.executableURL = URL(fileURLWithPath: wrapped.executable)
            process.arguments = wrapped.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command.text]
        }
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, ours in ours }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = writer
        process.standardError = writer
        let (exited, exit) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in exit.finish() }
        try process.run()

        let pid = process.processIdentifier
        let watchdog = Task {
            guard (try? await Task.sleep(for: timeout)) != nil else { return false }
            kill(pid, SIGTERM)
            if (try? await Task.sleep(for: grace)) != nil { kill(pid, SIGKILL) }
            return true
        }
        for await _ in exited {}
        watchdog.cancel()
        return Finished(
            status: process.terminationStatus, timedOut: await watchdog.value, output: try end(of: capture))
    }

    private static func end(of file: URL) throws -> String {
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        let size = try reader.seekToEnd()
        try reader.seek(toOffset: size > mostOutputRead ? size - mostOutputRead : 0)
        return String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self)
    }
}
