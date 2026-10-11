import Foundation

/// Said by itself during dictation, a few phrases edit the text Hark just typed instead of being typed: "scratch that",
/// "change their to there", and a small set of cursor and selection words. Each acts only on text Hark typed and can check
/// is still there (see `TypedSpan`), or on the current selection; none presses Return.
public enum DictationCommand: Equatable, Sendable {
    public enum Move: String, Sendable { case lastWord, line, all, start, end }

    case scratch
    case replace(old: String, new: String)
    case select(Move)
    /// Deletes what is selected, but only when something is.
    case deleteSelection
    case learn(String)

    public static func parse(_ heard: String) -> DictationCommand? {
        let words = normalizedWords(heard)
        guard !words.isEmpty, words.count <= 14 else { return nil }
        let text = words.joined(separator: " ")
        if ["scratch that", "scratch this", "undo dictation", "undo that dictation", "scratch that last part"].contains(text) {
            return .scratch
        }
        switch text {
        case "select last word": return .select(.lastWord)
        case "select line", "select this line": return .select(.line)
        case "select all", "select everything": return .select(.all)
        case "go to start", "go to the start", "go to the beginning": return .select(.start)
        case "go to end", "go to the end": return .select(.end)
        case "delete selection", "delete the selection", "delete selected", "delete that selection": return .deleteSelection
        default: break
        }
        for lead in ["learn the word ", "remember the word ", "learn the name ", "remember the name "] where text.hasPrefix(lead) {
            let word = String(text.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            if !word.isEmpty, word.split(separator: " ").count <= 3 { return .learn(word) }
        }
        for (lead, joiner) in [("change ", " to "), ("replace ", " with "), ("correct ", " to ")] where text.hasPrefix(lead) {
            let rest = String(text.dropFirst(lead.count))
            guard let split = rest.range(of: joiner) else { continue }
            let old = String(rest[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)
            let new = String(rest[split.upperBound...]).trimmingCharacters(in: .whitespaces)
            // "correct that to Priya" fixes the last word typed.
            if lead == "correct ", old == "that" { return .replace(old: "", new: new) }
            if !old.isEmpty, !new.isEmpty { return .replace(old: old, new: new) }
        }
        return nil
    }
}

/// Text Hark typed, found again in the box it was typed into. Nothing is changed unless the text just before the cursor is
/// exactly what was typed, so an edit never lands on words the user wrote.
public enum TypedSpan {
    /// The range (in UTF-16 units, as the accessibility API counts) of `span` when it ends exactly at `caret` in `value`.
    public static func range(of span: String, in value: String, caret: Int) -> NSRange? {
        let whole = value as NSString
        let length = (span as NSString).length
        guard length > 0, caret >= length, caret <= whole.length else { return nil }
        let candidate = NSRange(location: caret - length, length: length)
        return whole.substring(with: candidate) == span ? candidate : nil
    }

    /// The last place `old` appears inside the typed span (ignoring case), as a range in the whole value. An empty `old`
    /// means the last word.
    public static func target(_ old: String, inSpan span: NSRange, of value: String) -> NSRange? {
        let whole = value as NSString
        let typed = whole.substring(with: span)
        let text = typed as NSString
        if old.isEmpty {
            let trimmed = typed.trimmingCharacters(in: .whitespaces)
            guard let last = trimmed.split(separator: " ").last else { return nil }
            let found = text.range(of: String(last), options: .backwards)
            return found.location == NSNotFound ? nil : NSRange(location: span.location + found.location, length: found.length)
        }
        let found = text.range(of: old, options: [.backwards, .caseInsensitive])
        return found.location == NSNotFound ? nil : NSRange(location: span.location + found.location, length: found.length)
    }
}

extension Dictation {
    private static let marks: [(words: [String], mark: String, joinsBefore: Bool, endsSentence: Bool)] = [
        (["full", "stop"], ".", true, true), (["question", "mark"], "?", true, true),
        (["exclamation", "mark"], "!", true, true), (["exclamation", "point"], "!", true, true),
        (["comma"], ",", true, false), (["semicolon"], ";", true, false), (["colon"], ":", true, false),
        (["ellipsis"], "\u{2026}", true, false),
    ]

    /// Dictation with spoken punctuation and casing turned into characters: "hello comma world full stop" is "Hello, world."
    /// "literal comma" types the word. A plain table of punctuation words, so it names no app; it can be turned off.
    public static func tidy(_ heard: String, spokenPunctuation: Bool) -> String {
        guard spokenPunctuation else { return tidy(heard) }
        let flat = tidy(heard)
        var words = flat.split(separator: " ").map(String.init)
        var out: [String] = []
        var capitaliseNext = false
        var glueNext = false
        var casing: ((String) -> String)?
        var openQuote = false
        var index = 0
        func append(_ word: String) {
            var piece = word
            if let casing { piece = casing(piece) }
            casing = nil
            if capitaliseNext, let first = piece.first { piece = first.uppercased() + piece.dropFirst(); capitaliseNext = false }
            if glueNext, !out.isEmpty { out[out.count - 1] += piece; glueNext = false } else { out.append(piece) }
        }
        while index < words.count {
            let word = words[index]
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if lower == "literal", index + 1 < words.count {
                append(words[index + 1]); index += 2; continue
            }
            if let entry = marks.first(where: { entry in
                index + entry.words.count <= words.count
                    && (0..<entry.words.count).allSatisfy { words[index + $0].lowercased().trimmingCharacters(in: .punctuationCharacters) == entry.words[$0] }
            }), !out.isEmpty {
                out[out.count - 1] += entry.mark
                if entry.endsSentence { capitaliseNext = true }
                index += entry.words.count
                continue
            }
            if lower == "all", index + 2 < words.count, words[index + 1].lowercased() == "caps" {
                casing = { $0.uppercased() }; index += 2; continue
            }
            if lower == "capital", index + 1 < words.count {
                casing = { $0.prefix(1).uppercased() + $0.dropFirst() }; index += 1; continue
            }
            if lower == "no", index + 1 < words.count, words[index + 1].lowercased() == "space" {
                glueNext = true; index += 2; continue
            }
            if lower == "open", index + 1 < words.count, words[index + 1].lowercased() == "quote" {
                openQuote = true; index += 2; continue
            }
            if lower == "close", index + 1 < words.count, words[index + 1].lowercased() == "quote", !out.isEmpty {
                out[out.count - 1] += "\u{201D}"; openQuote = false; index += 2; continue
            }
            if openQuote { append("\u{201C}" + word); openQuote = false } else { append(word) }
            index += 1
        }
        words = out
        let text = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return "" }
        return first.uppercased() + text.dropFirst()
    }
}
