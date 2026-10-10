import Foundation
import HarkCore

/// Uses a command-line AI tool as a chat model. The tool is started with all of its own tools off, no
/// settings, no extensions and nothing saved, in an empty folder, so it can only answer in words. Its
/// answer is read by `CLIToolProtocol`, which keeps only calls to Hark's own tools.
public struct CLIChatModel: ChatModel {
    private static let timeout: TimeInterval = 30
    static let folder = FileManager.default.temporaryDirectory.appending(path: "hark-cli", directoryHint: .isDirectory)

    private let tool: ModelCLI
    private let model: String

    /// `model` is a short name ("haiku", "sonnet", "opus") or a full model name. Anything that is not made of
    /// plain name characters is replaced by Haiku, so a stray setting can never become an option for the tool.
    public init(_ tool: ModelCLI, model: String = "haiku") {
        self.tool = tool
        let plain = !model.isEmpty && model.count <= 60 && !model.hasPrefix("-")
            && model.allSatisfy { $0.isLetter || $0.isNumber || ".-_".contains($0) }
        self.model = plain ? model : "haiku"
    }

    /// Starts the tool's process, so the first question finds it ready. Called when the user presses the key.
    public func warmUp() {
        let session = CLISession.shared(for: tool, model: model, folder: Self.folder)
        Task { await session.warmUp() }
    }

    public func reply(to messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        // Without tools it is a plain question and answer, as the failed-command review asks.
        if tools.isEmpty {
            var question = ""
            for case .user(let text) in messages { question = text }
            let system = CLIToolProtocol.extraSystem(from: messages) ?? "Answer briefly."
            return ChatReply(text: try await ask(system: system, prompt: question), calls: [])
        }
        let system = CLIToolProtocol.system(extra: CLIToolProtocol.extraSystem(from: messages))
        let prompt = CLIToolProtocol.prompt(messages: messages, tools: tools)
        let answer = try await ask(system: system, prompt: prompt)
        guard let reply = CLIToolProtocol.parse(answer, tools: tools) else {
            throw CLIModelError(message: "\(tool.label) gave an answer Hark could not read.")
        }
        return reply
    }

    /// The answer's text. A running process is used when there is one; if the process cannot be kept running
    /// (an older or newer version of the tool that does not take messages this way), it is started for this
    /// question alone, as before.
    private func ask(system: String, prompt: String) async throws -> String {
        let session = CLISession.shared(for: tool, model: model, folder: Self.folder)
        let started = ContinuousClock.now
        do {
            return try await session.ask("\(system)\n\n\(prompt)", timeout: Self.timeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Only a quick failure means the way of asking does not work; a slow one is the model being slow.
            guard !Task.isCancelled, ContinuousClock.now - started < .seconds(8) else { throw error }
            let output = try await CLIProcess.run(
                tool.path, arguments: arguments(system: system), input: prompt, timeout: Self.timeout,
                folder: Self.folder)
            return try Self.answer(from: output)
        }
    }

    /// Claude Code, text only: no tools, no settings files, no extensions, nothing saved.
    private func arguments(system: String) -> [String] {
        ["-p", "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
         "--no-session-persistence", "--output-format", "json", "--model", model, "--effort", "low",
         "--system-prompt", system]
    }

    /// The text of the answer, from the tool's JSON wrapper.
    private static func answer(from output: String) throws -> String {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"),
              let data = String(output[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CLIModelError(message: "The tool answered in a form Hark does not know.") }
        if object["is_error"] as? Bool == true {
            throw CLIModelError(message: "The tool reported a problem: \((object["result"] as? String ?? "unknown").prefix(160))")
        }
        guard let result = object["result"] as? String else {
            throw CLIModelError(message: "The tool gave no answer.")
        }
        return result
    }
}
