import Foundation

/// Reads a model's answer to "what did these failed commands probably mean?". Models wrap answers in
/// prose and code fences and sometimes get things wrong, so only well-formed pairs of short plain
/// phrases are kept, and anything that looks like a command for a shell is thrown away. What it keeps
/// is still only a suggestion: it is shown to work first, and then the user decides.
public enum ReviewParser {
    public struct Pair: Sendable, Equatable {
        public var said: String
        public var meant: String
    }

    private static let mostWords = 8
    private static let notAllowed = CharacterSet(charactersIn: "$`|;&<>\\{}[]()*~/\"")

    public static func parse(_ reply: String, asked: [String]) -> [Pair] {
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        let allowed = Set(asked)
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let saidText = row["said"] as? String, let meantText = row["meant"] as? String,
                  isPlain(saidText), isPlain(meantText)
            else { return nil }
            let said = Learner.normalize(saidText), meant = Learner.normalize(meantText)
            // Only the commands that were asked about: a model cannot add its own.
            guard !said.isEmpty, !meant.isEmpty, said != meant, allowed.contains(said),
                  said.split(separator: " ").count <= mostWords, meant.split(separator: " ").count <= mostWords,
                  seen.insert(said).inserted
            else { return nil }
            return Pair(said: said, meant: meant)
        }
    }

    /// A short plain phrase: no shell symbols, no line breaks, no sentences.
    private static func isPlain(_ text: String) -> Bool {
        text.count <= 80 && text.rangeOfCharacter(from: notAllowed) == nil
            && !text.contains("\n") && !text.contains(". ")
    }
}
