import Foundation

/// Turns what was heard into what gets typed. Dictation types the user's own words: nothing is
/// rewritten by a model and no word is added, so this only removes noise.
public enum Dictation {
    private static let fillers: Set<String> = ["um", "uh", "er", "erm", "hmm", "mm", "uhm", "umm"]

    public static func tidy(_ heard: String) -> String {
        // Line breaks become spaces: a typed return could send or run what is in the box.
        let flat = heard.unicodeScalars.map { CharacterSet.newlines.contains($0) ? " " : String($0) }.joined()
        let kept = flat.split(whereSeparator: \.isWhitespace).compactMap { word -> String? in
            let bare = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if fillers.contains(bare) { return nil }
            return String(word)
        }
        var text = kept.joined(separator: " ")
        // A filler between commas leaves ", ," behind; collapse it.
        while text.contains(", ,") { text = text.replacingOccurrences(of: ", ,", with: ",") }
        text = text.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return "" }
        return first.uppercased() + text.dropFirst()
    }
}
