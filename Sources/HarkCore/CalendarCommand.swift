import Foundation

/// Questions about the user's calendar, answered from the calendar on this Mac (read-only): "what's next", "what's my
/// day look like", "am I free at three", "join my next meeting", "get ready for my next meeting".
public enum CalendarCommand: Equatable, Sendable {
    case next
    case today
    case free(hour: Int, minute: Int)
    case join
    case getReady

    public static func parse(_ transcript: String) -> CalendarCommand? {
        let words = normalizedWords(transcript)
        guard !words.isEmpty, words.count <= 10 else { return nil }
        let text = words.joined(separator: " ").replacingOccurrences(of: "whats ", with: "whats ")
        if ["whats next", "whats next", "what is next", "whats my next meeting", "what is my next meeting",
            "next meeting", "when is my next meeting", "whats next on my calendar"].contains(text) { return .next }
        if ["whats my day look like", "what does my day look like", "whats on today", "what is on today",
            "whats on my calendar", "what is on my calendar", "my day", "show my day", "what do i have today"].contains(text) {
            return .today
        }
        if text.hasPrefix("join my next meeting") || text == "join the meeting" || text == "join my meeting"
            || text == "join the next meeting" || text == "join the call" { return .join }
        if text.hasPrefix("get ready for my next meeting") || text == "get ready for my meeting" || text == "get ready for the meeting" {
            return .getReady
        }
        if text.hasPrefix("am i free at ") || text.hasPrefix("am i free around ") || text.hasPrefix("am i busy at ") {
            return time(in: Array(words.drop { $0 != "at" && $0 != "around" }.dropFirst()))
        }
        return nil
    }

    /// "3", "3 pm", "three thirty", "15 30", "3:30 pm" as words.
    static func time(in words: [String]) -> CalendarCommand? {
        var hours = words
        let pm = hours.contains("pm") || hours.contains("p") && hours.contains("m")
        let am = hours.contains("am")
        hours.removeAll { ["pm", "am", "p", "m", "o", "clock", "oclock"].contains($0) }
        guard let first = hours.first, var hour = Int(first), (0...23).contains(hour) else { return nil }
        let minute = hours.count > 1 ? (Int(hours[1]) ?? 0) : 0
        if pm, hour < 12 { hour += 12 }
        if am, hour == 12 { hour = 0 }
        // With no am or pm, an hour up to six is taken as the afternoon, the way people say it at a desk.
        if !pm, !am, (1...6).contains(hour) { hour += 12 }
        return .free(hour: hour, minute: min(max(minute, 0), 59))
    }

    /// The first web address in text such as an event's location or notes.
    public static func firstLink(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            guard let range = text.range(of: #"https?://[^\s<>"')\]]+"#, options: .regularExpression) else { continue }
            if let url = URL(string: String(text[range])) { return url }
        }
        return nil
    }
}
