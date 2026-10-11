import Foundation

/// "Set a 10 minute timer", "remind me in 20 minutes to check the oven", "timer for an hour": a countdown kept by Hark
/// while it runs. It is announced on screen with a sound; it does not survive quitting Hark.
public struct TimerCommand: Equatable, Sendable {
    public var seconds: Int
    public var label: String?

    public static func parse(_ transcript: String) -> TimerCommand? {
        let words = normalizedWords(transcript)
        guard !words.isEmpty, words.count <= 14 else { return nil }
        let isTimer = words.contains("timer") || words.starts(with: ["remind", "me", "in"])
            || words.starts(with: ["set", "a", "reminder", "in"]) || words.starts(with: ["countdown"])
        guard isTimer, let seconds = duration(in: words), seconds >= 1, seconds <= 24 * 3600 else { return nil }
        var label: String?
        if let to = words.firstIndex(of: "to"), to + 1 < words.count, words.starts(with: ["remind"]) {
            label = words[(to + 1)...].joined(separator: " ")
        }
        return TimerCommand(seconds: seconds, label: label)
    }

    private static func duration(in words: [String]) -> Int? {
        var total = 0
        var found = false
        var index = 0
        while index < words.count {
            var amount: Double?
            if words[index] == "a" || words[index] == "an", index + 1 < words.count { amount = 1 }
            else if let value = Double(words[index]) { amount = value }
            else if words[index] == "half", index + 2 < words.count, words[index + 1] == "an" { amount = 0.5; index += 1 }
            if let amount, index + 1 < words.count {
                let unit = words[index + 1]
                let scale: Double? = ["second", "seconds", "sec", "secs"].contains(unit) ? 1
                    : ["minute", "minutes", "min", "mins"].contains(unit) ? 60
                    : ["hour", "hours", "hr", "hrs"].contains(unit) ? 3600 : nil
                if let scale { total += Int(amount * scale); found = true; index += 1 }
            }
            index += 1
        }
        return found ? total : nil
    }

    /// "10 minutes", "1 hour 30 minutes".
    public var spoken: String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, rest = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if rest > 0 && hours == 0 { parts.append("\(rest) \(rest == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }
}

/// "Focus on shop": bring forward the windows and tabs that belong to one project.
public enum FocusCommand {
    public static func project(in transcript: String) -> String? {
        let words = normalizedWords(transcript)
        for lead in [["focus", "on"], ["focus"], ["work", "on"], ["switch", "to", "the"], ["go", "to", "the"]] where words.starts(with: lead) {
            var rest = Array(words.dropFirst(lead.count))
            // "switch to the shop project": only with the word "project", so plain switching keeps its own rule.
            if lead.first == "switch" || lead.first == "go" {
                guard rest.last == "project" || rest.last == "workspace" else { return nil }
                rest.removeLast()
            }
            if rest.first == "the" { rest.removeFirst() }
            if rest.last == "project" { rest.removeLast() }
            return rest.isEmpty || rest.count > 4 ? nil : rest.joined(separator: " ")
        }
        return nil
    }
}
