import Foundation

/// A service Hark can ask, with the address that service answers on, so the user picks a name
/// instead of typing a web address.
public struct ModelProvider: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let address: String
    /// Whether the service wants a key before it will list or run models.
    public let needsKey: Bool

    public static let gemini = ModelProvider(
        id: "gemini", name: "Google Gemini",
        address: "https://generativelanguage.googleapis.com/v1beta/openai", needsKey: true)
    public static let openAI = ModelProvider(
        id: "openai", name: "OpenAI", address: "https://api.openai.com/v1", needsKey: true)
    public static let ollama = ModelProvider(
        id: "ollama", name: "Ollama on this Mac", address: "http://127.0.0.1:11434/v1", needsKey: false)
    public static let all = [gemini, openAI, ollama]

    /// The provider whose address this is, ignoring a trailing slash, or nil for any other address.
    public static func matching(address: String) -> ModelProvider? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return all.first { $0.address.caseInsensitiveCompare(cleaned) == .orderedSame }
    }
}

/// Reads the answer to "which models do you have?" from any service that speaks the OpenAI format.
public enum ModelList {
    /// Names that are not for chatting. They would never answer a command, so they are not offered.
    private static let notForChat = [
        "embed", "tts", "whisper", "dall-e", "image", "imagen", "veo", "moderation", "audio",
        "realtime", "transcribe", "aqa", "vision-preview", "rerank", "live", "bidi", "robotics", "computer-use",
    ]

    /// False for a name that can never answer a command, such as a streaming-only or embedding model.
    public static func canChat(_ name: String) -> Bool {
        !notForChat.contains { name.lowercased().contains($0) }
    }

    public static func parse(_ data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        // OpenAI, Gemini and Ollama answer {"data": [{"id": …}]}. Gemini's own format is {"models": [{"name": …}]}.
        let rows = (object["data"] as? [[String: Any]]) ?? (object["models"] as? [[String: Any]]) ?? []
        let names = rows.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst("models/".count)) : $0 }
            .filter(canChat)
        return Array(Set(names)).sorted()
    }
}
