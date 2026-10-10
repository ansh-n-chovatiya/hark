import Foundation
import HarkCore

/// One long-lived `claude` process that answers questions as they arrive, instead of starting a program for
/// every command. A fresh start costs several seconds before the model even begins; a running one answers in
/// about one. It is started when the user presses the key (while they are still speaking), so nothing is
/// started between key release and the action.
///
/// Every message is an independent task: the process is told so, and it is restarted after a few requests so
/// it never carries a long conversation, and after a timeout or a cancelled request, so a late answer can
/// never be taken for the next one. The process has all of its own tools, settings and extensions off.
actor CLISession {
    private static let maxRequests = 8
    private static let idleLimit: TimeInterval = 10 * 60
    private static let instructions = """
        You are the planning step of Hark, a voice assistant for the Mac. Every message is a separate, independent \
        task: ignore all earlier messages and follow only the instructions in the latest one. Answer exactly in the \
        form that message asks for.
        """

    private static let sessions = Registry()

    /// One session per tool and model, shared by everything that asks.
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [String: CLISession] = [:]

        func session(for tool: ModelCLI, model: String, folder: URL) -> CLISession {
            lock.withLock {
                let key = "\(tool.path)#\(model)"
                if let existing = all[key] { return existing }
                let made = CLISession(tool: tool, model: model, folder: folder)
                all[key] = made
                return made
            }
        }
    }

    static func shared(for tool: ModelCLI, model: String, folder: URL) -> CLISession {
        sessions.session(for: tool, model: model, folder: folder)
    }

    /// What is read from the process, kept between requests so a partly read line is not lost.
    private final class Reader: @unchecked Sendable {
        let handle: FileHandle
        var pending = Data()
        init(_ handle: FileHandle) { self.handle = handle }
    }

    private let tool: ModelCLI
    private let model: String
    private let folder: URL
    private var process: Process?
    private var input: FileHandle?
    private var reader: Reader?
    private var served = 0
    private var lastUsed = Date.distantPast
    private var idleTask: Task<Void, Never>?
    private var locked = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(tool: ModelCLI, model: String, folder: URL) {
        self.tool = tool
        self.model = model
        self.folder = folder
    }

    /// Whether a process is running right now.
    var isRunning: Bool { process?.isRunning == true }

    /// Starts the process if it is not running, so the first question finds it ready.
    func warmUp() {
        try? ensureRunning()
    }

    func ask(_ text: String, timeout: TimeInterval) async throws -> String {
        await acquire()
        defer { release() }
        // Dropped while waiting for its turn: nothing is sent, so nothing is left to answer later.
        try Task.checkCancellation()
        try ensureRunning()
        guard let input, let reader, let process else { throw CLIModelError(message: "The tool is not running.") }
        let message = ["type": "user", "message": ["role": "user", "content": text]] as [String: Any]
        let line = try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8)
        do {
            try input.write(contentsOf: line)
        } catch {
            stop()
            throw CLIModelError(message: "The tool stopped before it could be asked.")
        }
        served += 1
        lastUsed = Date()
        do {
            let answer = try await withTaskCancellationHandler {
                try await Self.readAnswer(from: reader, process: process, timeout: timeout)
            } onCancel: {
                // A request that is dropped may still be answered later; the process is not trusted after that.
                if process.isRunning { process.terminate() }
            }
            retireIfWorn()
            scheduleIdleStop()
            return answer
        } catch {
            stop()
            throw error
        }
    }

    // MARK: Process

    private func ensureRunning() throws {
        if let process, process.isRunning, Date().timeIntervalSince(lastUsed) < Self.idleLimit || served == 0 { return }
        stop()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.path)
        process.arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--tools", "",
            "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
            "--model", model, "--effort", "low", "--system-prompt", Self.instructions,
        ]
        process.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        let extra = ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].map { NSString(string: $0).expandingTildeInPath }
        environment["PATH"] = (extra + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw CLIModelError(message: "The tool could not be started: \(error.localizedDescription)")
        }
        self.process = process
        input = stdin.fileHandleForWriting
        reader = Reader(stdout.fileHandleForReading)
        served = 0
        lastUsed = Date()
        scheduleIdleStop()
    }

    private func stop() {
        idleTask?.cancel()
        idleTask = nil
        if let process, process.isRunning { process.terminate() }
        try? input?.close()
        process = nil
        input = nil
        reader = nil
        served = 0
    }

    /// After a few requests the process is replaced by a fresh, ready one, so it never carries a long history.
    private func retireIfWorn() {
        guard served >= Self.maxRequests else { return }
        stop()
        try? ensureRunning()
    }

    /// An unused process is stopped after a while, so it does not sit in memory for ever.
    private func scheduleIdleStop() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleLimit))
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle()
        }
    }

    private func stopIfIdle() {
        if !locked, Date().timeIntervalSince(lastUsed) >= Self.idleLimit - 1 { stop() }
    }

    // MARK: One request at a time

    private func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            locked = false
        } else {
            waiting.removeFirst().resume()
        }
    }

    // MARK: Reading

    /// Reads lines until the answer arrives, on a thread of its own because reading blocks. The process is
    /// stopped if it takes longer than `timeout`, which ends the read.
    private static func readAnswer(from reader: Reader, process: Process, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                defer { timer.cancel() }
                while true {
                    while let newline = reader.pending.firstIndex(of: 0x0A) {
                        let line = reader.pending[reader.pending.startIndex..<newline]
                        reader.pending.removeSubrange(reader.pending.startIndex...newline)
                        if let outcome = Self.answer(inLine: Data(line)) {
                            continuation.resume(with: outcome)
                            return
                        }
                    }
                    let chunk = reader.handle.availableData
                    if chunk.isEmpty {
                        continuation.resume(throwing: CLIModelError(message: process.isRunning
                            ? "The tool stopped answering." : "The tool did not answer in time or stopped."))
                        return
                    }
                    reader.pending.append(chunk)
                }
            }
        }
    }

    /// The answer in one line of the tool's output, if that line is the final result.
    static func answer(inLine line: Data) -> Result<String, Error>? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "result"
        else { return nil }
        if object["is_error"] as? Bool == true {
            return .failure(CLIModelError(message: "The tool reported a problem: \((object["result"] as? String ?? "unknown").prefix(160))"))
        }
        guard let result = object["result"] as? String else { return .failure(CLIModelError(message: "The tool gave no answer.")) }
        return .success(result)
    }
}
