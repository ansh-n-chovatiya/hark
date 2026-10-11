import Foundation

/// Questions about local servers, answered from what the system reports about listening ports, with no terminal:
/// "what's on 3000", "what's running", "open localhost 5173", "tell me when 3000 is up".
public enum PortCommand: Equatable, Sendable {
    case whatsOn(Int?)
    case open(Int)
    case tellWhenUp(Int)

    public static func parse(_ transcript: String) -> PortCommand? {
        let words = normalizedWords(transcript)
        guard !words.isEmpty, words.count <= 10 else { return nil }
        let text = words.joined(separator: " ")
        let port = words.compactMap { Int($0) }.first { (1...65535).contains($0) }
        if text.hasPrefix("tell me when"), words.contains("up") || words.contains("ready") || words.contains("running"),
           let port { return .tellWhenUp(port) }
        if let port, text.hasPrefix("what s on") || text.hasPrefix("whats on") || text.hasPrefix("what is on")
            || text.hasPrefix("what is running on") || text.hasPrefix("what s running on") || text.hasPrefix("who is on")
            || text.hasPrefix("who has") || text.hasPrefix("what is using") || text.hasPrefix("what s using") {
            return .whatsOn(port)
        }
        if ["what s running", "whats running", "what is running", "what servers are running", "what is listening",
            "what s listening", "show listening ports", "list ports"].contains(text) { return .whatsOn(nil) }
        if let port, words.contains("localhost") || words.contains("local") && words.contains("host"),
           ["open", "show", "go", "switch"].contains(words.first ?? "") { return .open(port) }
        return nil
    }
}
