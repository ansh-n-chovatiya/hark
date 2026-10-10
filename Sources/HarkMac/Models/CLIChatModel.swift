import Foundation
import HarkCore

/// Uses a command-line AI tool as a chat model. The tool is started with all of its own tools off, no
/// settings, no extensions and nothing saved, in an empty folder, so it can only answer in words. Its
/// answer is read by `CLIToolProtocol`, which keeps only calls to Hark's own tools.
public struct CLIChatModel: ChatModel {
    private static let timeout: TimeInterval = 30
    private static let folder = FileManager.default.temporaryDirectory.appending(path: "hark-cli", directoryHint: .isDirectory)

    private let tool: ModelCLI

    public init(_ tool: ModelCLI) {
        self.tool = tool
    }

    public func reply(to messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        // Without tools it is a plain question and answer, as the failed-command review asks.
        if tools.isEmpty {
            var question = ""
            for case .user(let text) in messages { question = text }
            let system = CLIToolProtocol.extraSystem(from: messages) ?? "Answer briefly."
            let output = try await CLIProcess.run(
                tool.path, arguments: Self.arguments(for: tool, system: system), input: question, timeout: Self.timeout,
                folder: Self.folder)
            return ChatReply(text: try Self.answer(from: output), calls: [])
        }
        let system = CLIToolProtocol.system(extra: CLIToolProtocol.extraSystem(from: messages))
        let prompt = CLIToolProtocol.prompt(messages: messages, tools: tools)
        let output = try await CLIProcess.run(
            tool.path, arguments: Self.arguments(for: tool, system: system), input: prompt, timeout: Self.timeout,
            folder: Self.folder)
        let answer = try Self.answer(from: output)
        guard let reply = CLIToolProtocol.parse(answer, tools: tools) else {
            throw CLIModelError(message: "\(tool.label) gave an answer Hark could not read.")
        }
        return reply
    }

    /// Claude Code, text only: no tools, no settings files, no extensions, nothing saved.
    private static func arguments(for tool: ModelCLI, system: String) -> [String] {
        ["-p", "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
         "--no-session-persistence", "--output-format", "json", "--model", "haiku", "--effort", "low",
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
