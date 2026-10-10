import Foundation
import HarkCore

private struct ChatModelError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to any OpenAI-compatible chat endpoint with tool calling. Without a key only an address
/// on this Mac is accepted, so what the user has open leaves the machine only when they set up a
/// hosted model on purpose.
public struct OpenAIChatModel: ChatModel {
    private static let maxTokens = 600

    private let endpoint: URL
    private let models: [String]
    private let key: String
    private let session: URLSession
    private let timeout: TimeInterval
    public let isLocal: Bool

    /// `models` may hold several names separated by commas; all are asked at once and the first
    /// usable reply wins. Returns nil for an unusable address, or a remote one with no key.
    public init?(url: String, models: String, key: String, timeout: TimeInterval = 6) {
        guard let base = URL(string: url), let host = base.host() else { return nil }
        isLocal = ["127.0.0.1", "localhost", "::1"].contains(host)
        guard isLocal || !key.isEmpty else { return nil }
        // A name that can never answer (a streaming-only model, say) is left out instead of wasting a request.
        let names = models.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ModelList.canChat($0) }
        guard !names.isEmpty else { return nil }
        endpoint = base.appending(path: "chat/completions")
        self.models = names
        self.key = key
        self.timeout = timeout
        session = URLSession(configuration: .ephemeral)
    }

    public func reply(to messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        return try await withThrowingTaskGroup(of: ChatReply.self) { group in
            for model in models {
                group.addTask { try await ask(model, messages, tools) }
            }
            var lastError: Error = ChatModelError(message: "The model gave no reply")
            while !group.isEmpty {
                do {
                    guard let reply = try await group.next() else { break }
                    group.cancelAll()
                    return reply
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
    }

    /// Loads a local model into memory. Does nothing useful for a hosted one.
    public func warmUp() async {
        guard isLocal, let model = models.first else { return }
        let body: [String: Any] = [
            "model": model, "max_tokens": 1, "messages": [["role": "user", "content": "hi"]],
        ]
        _ = try? await post(body)
    }

    private func ask(_ model: String, _ messages: [ChatMessage], _ tools: [ToolSpec]) async throws -> ChatReply {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { wire($0) },
            "max_tokens": Self.maxTokens,
            "temperature": 0,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map(Self.wire)
            body["tool_choice"] = "auto"
        }
        // Hosted models think before answering unless told to think less, which costs seconds here.
        // Which levels a model accepts differs ("minimal" is refused by some Gemini models), so a
        // refusal moves on to the next level, and the last try leaves the setting out.
        let efforts: [String?] = isLocal ? [nil] : ["minimal", "low", nil]
        for (index, effort) in efforts.enumerated() {
            body["reasoning_effort"] = effort
            if index == efforts.count - 1 { body["temperature"] = nil }
            do {
                return try parse(try await post(body))
            } catch let rejected as FieldRejected {
                if index == efforts.count - 1 {
                    throw ChatModelError(message: "The model service refused the request: \(rejected.detail)")
                }
            }
        }
        throw ChatModelError(message: "The model refused every setting Hark tried")
    }

    private struct FieldRejected: Error { let detail: String }

    private func post(_ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ChatModelError(message: "The model did not answer in time")
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw ChatModelError(message: "The model could not be reached (\(error.code.rawValue))")
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw ChatModelError(message: "The model sent an unreadable reply")
        }
        guard (200..<300).contains(status) else {
            let detail = errorDetail(data)
            if status == 400, ["reasoning", "thinking", "temperature"].contains(where: detail.lowercased().contains) {
                throw FieldRejected(detail: detail)
            }
            if status == 429 {
                throw ChatModelError(message: "The online model's quota is used up (error 429). It works again when the quota resets, or choose another model.")
            }
            throw ChatModelError(message: "The model service returned error \(status)\(detail.isEmpty ? "" : ": \(detail)")")
        }
        return data
    }

    private func errorDetail(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        if let json = try? JSONSerialization.jsonObject(with: data) {
            let object = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
            if let message = (object?["error"] as? [String: Any])?["message"] as? String ?? object?["message"] as? String {
                text = message
            }
        }
        if !key.isEmpty { text = text.replacingOccurrences(of: key, with: "[key]") }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.prefix(160))
    }

    private func parse(_ data: Data) throws -> ChatReply {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw ChatModelError(message: "The model sent a reply that could not be read") }
        let text = (message["content"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let calls = (message["tool_calls"] as? [[String: Any]] ?? []).enumerated().compactMap(Self.call)
        if text == nil && calls.isEmpty { throw ChatModelError(message: "The model sent an empty reply") }
        return ChatReply(text: text, calls: calls)
    }

    private static func call(_ index: Int, _ raw: [String: Any]) -> ToolCall? {
        guard let function = raw["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
        let id = (raw["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "call_\(index)"
        return ToolCall(id: id, name: name, arguments: arguments(function["arguments"]))
    }

    private static func arguments(_ raw: Any?) -> JSONValue {
        if let string = raw as? String {
            guard let data = string.data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return .object([:]) }
            return value
        }
        guard let raw, JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .object([:]) }
        return value
    }

    private func wire(_ message: ChatMessage) -> [String: Any] {
        switch message {
        case .system(let text):
            return ["role": "system", "content": text]
        case .user(let text):
            return ["role": "user", "content": text]
        case .assistant(let text, let calls):
            var wire: [String: Any] = ["role": "assistant", "content": text ?? ""]
            if !calls.isEmpty {
                wire["tool_calls"] = calls.map { call -> [String: Any] in
                    var wireCall: [String: Any] = [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": Self.jsonString(call.arguments)],
                    ]
                    // Gemini refuses a replayed tool call without the signature of the thinking
                    // that produced it, which Hark does not keep. Google documents this value as
                    // the way to skip that check.
                    if !isLocal {
                        wireCall["extra_content"] = ["google": ["thought_signature": "skip_thought_signature_validator"]]
                    }
                    return wireCall
                }
            }
            return wire
        case .tool(let callID, _, let output):
            return ["role": "tool", "tool_call_id": callID, "content": output]
        }
    }

    private static func wire(_ tool: ToolSpec) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(tool.parameters))) ?? [:],
            ] as [String: Any],
        ]
    }

    private static func jsonString(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Prefers `primary`, but takes `fallback`'s reply if `primary` has not answered within `headStart`
/// or has failed.
public struct FallbackChatModel: ChatModel {
    private final class Source: @unchecked Sendable {
        private let lock = NSLock()
        private var value = "primary"
        var current: String {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    private final class Claim: @unchecked Sendable {
        private let lock = NSLock()
        private var taken = false
        func take() -> Bool {
            lock.withLock {
                defer { taken = true }
                return !taken
            }
        }
    }

    private let primary: any ChatModel
    private let fallback: any ChatModel
    private let headStart: Duration
    private let source = Source()

    public init(primary: any ChatModel, fallback: any ChatModel, headStart: Duration = .seconds(2)) {
        self.primary = primary
        self.fallback = fallback
        self.headStart = headStart
    }

    /// "primary" or "fallback", for logging.
    public var lastSource: String { source.current }

    public func reply(to messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        let (primary, fallback, headStart) = (self.primary, self.fallback, self.headStart)
        let fallbackStarted = Claim()
        return try await withThrowingTaskGroup(of: (String, ChatReply).self) { group in
            group.addTask {
                do {
                    return ("primary", try await primary.reply(to: messages, tools: tools))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard fallbackStarted.take() else { throw error }
                    return ("fallback", try await fallback.reply(to: messages, tools: tools))
                }
            }
            group.addTask {
                try await Task.sleep(for: headStart)
                guard fallbackStarted.take() else { throw ChatModelError(message: "The fallback was already asked") }
                return ("fallback", try await fallback.reply(to: messages, tools: tools))
            }
            var primaryError: Error?
            while !group.isEmpty {
                do {
                    guard let (name, reply) = try await group.next() else { break }
                    group.cancelAll()
                    source.current = name
                    return reply
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    primaryError = primaryError ?? error
                }
            }
            throw primaryError ?? ChatModelError(message: "The model gave no reply")
        }
    }
}
