import Foundation

/// Lowercased words of `text`, split on anything that is not a letter or a digit.
func normalizedWords(_ text: String) -> [String] {
    var words: [String] = []
    var current = ""
    for character in text.lowercased() {
        if character.isLetter || character.isNumber {
            current.append(character)
        } else if character == "'" || character == "’" {
            continue
        } else if !current.isEmpty {
            words.append(current)
            current = ""
        }
    }
    if !current.isEmpty { words.append(current) }
    return words
}

private struct Phrase: Sendable {
    let spoken: [String]
    let replacement: [String]
}

private func phrases(_ table: [String: String]) -> [Phrase] {
    table
        .map { Phrase(spoken: $0.key.split(separator: " ").map(String.init), replacement: [$0.value]) }
        .sorted { $0.spoken.count > $1.spoken.count }
}

private func replacing(_ phrases: [Phrase], in words: [String]) -> [String] {
    var result: [String] = []
    var index = 0
    while index < words.count {
        if let phrase = phrases.first(where: { words[index...].starts(with: $0.spoken) }) {
            result.append(contentsOf: phrase.replacement)
            index += phrase.spoken.count
        } else {
            result.append(words[index])
            index += 1
        }
    }
    return result
}

private func strippingLead(_ leads: [[String]], from words: [String]) -> [String] {
    var rest = words[...]
    while let lead = leads.first(where: { rest.starts(with: $0) }) {
        rest = rest.dropFirst(lead.count)
    }
    return Array(rest)
}

/// How speech recognisers commonly write numbers, mapped to one spelling. Names are not listed here: a name said as
/// two words ("you tube") is joined when the one-word name is known (see `RuleParser.names`), and the other ways to
/// say an app's name are read from the installed apps.
private let looseSpellings = phrases([
    "local host": "localhost",
    "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
    "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
])

/// Includes the homophones a recogniser writes when a number is said on its own.
private let pickNumbers: [String: String] = [
    "1": "1", "2": "2", "3": "3", "4": "4", "5": "5",
    "won": "1", "to": "2", "too": "2", "for": "4",
    "first": "1", "second": "2", "third": "3", "fourth": "4", "fifth": "5",
    // Answers to a yes-or-no question, which the overlay numbers 1 and 2.
    "yes": "1", "yeah": "1", "yep": "1", "confirm": "1", "no": "2", "nope": "2", "cancel": "2",
]
private let pickLeadWords: Set<String> = ["please", "number", "pick", "option", "choose", "select"]

private let compoundWords: Set<String> = [
    "and", "then", "all", "every", "everything", "each", "both", "except", "other", "others", "rest",
]

private let deletionWords: Set<String> = [
    "delete", "deletes", "deleting", "erase", "wipe", "shred", "trash", "bin", "uninstall", "format",
]

/// True when a command asks to delete or destroy something. Hark never does that, whatever a
/// model makes of the sentence, so such commands are turned away before anything else looks at
/// them. Closing a tab or quitting an app is not deleting.
public func asksToDelete(_ transcript: String) -> Bool {
    !deletionWords.isDisjoint(with: normalizedWords(transcript))
}

private let scriptEndings: Set<String> = ["sh", "zsh", "bash", "py", "js", "ts", "rb", "command"]
private let runWords: Set<String> = ["run", "execute"]

/// True when the command asks for a script or a typed command to be run ("run start.sh in the
/// terminal"). Hark runs commands only from routines the user wrote, so the honest answer to
/// this is to say so at once rather than to try.
public func asksToRunAScript(_ transcript: String) -> Bool {
    let words = normalizedWords(transcript)
    guard !runWords.isDisjoint(with: words) else { return false }
    // "start.sh" arrives as two words, "start" and "sh".
    let namesAScript = words.dropFirst().contains(where: scriptEndings.contains)
    return namesAScript || words.contains("script")
}

private let folderWords: Set<String> = ["folder", "folders", "directory", "directories", "dir"]
private let looseKindWords: Set<String> = ["project", "repo", "repository"]

/// True when the command names a folder, as opposed to a file inside one.
public func asksForFolder(_ transcript: String) -> Bool {
    !folderWords.isDisjoint(with: normalizedWords(transcript))
}

/// True when a command asks for several things or a whole group ("close all tabs except this
/// one", "open X and Y"). The one-verb, one-target rules cannot express those.
public func looksCompound(_ transcript: String) -> Bool {
    !compoundWords.isDisjoint(with: normalizedWords(transcript))
}

private let fillerWords: Set<String> = [
    "the", "a", "an", "please", "hey", "hark", "um", "uh", "ok", "okay", "just",
    "this", "that", "me", "my", "for", "of",
    "which", "has", "have", "having", "where", "is", "are", "showing", "called", "named",
]

/// Left at the end of a description by speech such as "the tab which has the recorder open".
private let trailingNoise: Set<String> = ["open", "opened", "running", "up", "now"]

private let newTabMarkers: Set<String> = ["new", "empty", "blank", "fresh"]
private let newTabNoise: Set<String> = [
    "open", "new", "empty", "blank", "fresh", "tab", "in", "on", "create", "make",
    "start", "another", "and", "with",
]

private let politeLeads: [[String]] = [
    ["can", "you"], ["could", "you"], ["would", "you"], ["will", "you"],
    ["i", "want", "to"], ["i", "would", "like", "to"], ["id", "like", "to"], ["lets"],
]

/// What was heard, with names and numbers in one spelling.
func heardWords(_ transcript: String) -> [String] {
    replacing(looseSpellings, in: normalizedWords(transcript))
}

/// The words that carry a command: no filler and no polite opening.
func commandWords(_ heard: [String]) -> [String] {
    strippingLead(politeLeads, from: heard.filter { !fillerWords.contains($0) })
}

private struct VerbLead: Sendable {
    let words: [String]
    let verb: Verb
}

/// Written after filler is removed, so "save this as" is "save as". Longest lead is tried first.
private let verbLeads: [VerbLead] = [
    ("switch to", Verb.open), ("go to", .open), ("jump to", .open), ("bring up", .open),
    ("switch", .open), ("open", .open), ("launch", .open), ("show", .open), ("find", .open), ("focus", .open),
    ("close all duplicate tabs", .closeDuplicates), ("close duplicate tabs", .closeDuplicates),
    ("close all duplicates", .closeDuplicates), ("close duplicates", .closeDuplicates),
    ("close duplicate", .closeDuplicates), ("remove duplicate tabs", .closeDuplicates),
    ("close", .close),
    ("paste", .paste),
    ("save workspace as", .save), ("save setup as", .save), ("remember setup as", .save),
    ("save as", .save), ("save", .save),
    ("restore workspace", .restore), ("open workspace", .restore), ("restore", .restore),
    ("hide", .hide),
    ("quit", .quit), ("exit", .quit),
    ("run", .run),
    ("undo", .undo),
]
.map { VerbLead(words: $0.0.split(separator: " ").map(String.init), verb: $0.1) }
.sorted { $0.words.count > $1.words.count }

private let kindWords: [String: [ItemKind]] = [
    "tab": [.tab], "tabs": [.tab],
    "window": [.window], "windows": [.window],
    "file": [.file], "files": [.file], "folder": [.file], "folders": [.file],
    "directory": [.file], "directories": [.file], "dir": [.file],
    "app": [.app], "apps": [.app], "application": [.app],
    "workspace": [.workspace], "workspaces": [.workspace],
    // A project is open as an editor window, or else it is a folder on disk.
    "project": [.window, .file], "repo": [.window, .file], "repository": [.window, .file],
]

private let ownerMarkers: Set<String> = ["from", "in"]

public struct RuleParser: Sendable {
    private let aliases: [Phrase]
    /// "Open a Brave tab" with nothing else said can only mean a new one: the words that can name a browser.
    private let browserWords: Set<String>
    /// One-word names known now (apps, windows, tabs, sites), lower case. Speech often splits such a name in two.
    private let compounds: Set<String>

    public init(aliases: [String: String], browserWords: Set<String> = ["browser"], names: [String] = []) {
        self.browserWords = browserWords
        compounds = Set(names.map { $0.lowercased() }.filter { name in
            name.count >= 4 && !name.contains(" ") && name.allSatisfy { $0.isLetter || $0.isNumber }
        })
        self.aliases = aliases
            .map { spoken, real in
                Phrase(
                    spoken: RuleParser.targetWords(spoken),
                    replacement: [real.lowercased().trimmingCharacters(in: .whitespaces)]
                )
            }
            .filter { !$0.spoken.isEmpty }
            .sorted { $0.spoken.count > $1.spoken.count }
    }

    /// The transcript with the user's own names swapped in ("the arc" becomes "the hark"), for a
    /// reader that does not know those names.
    public func applyingNames(to transcript: String) -> String {
        replacing(aliases, in: joiningCompounds(replacing(looseSpellings, in: normalizedWords(transcript)))).joined(separator: " ")
    }

    /// "you tube" is "youtube" when a name "youtube" is known; a split name is never joined into one that is not.
    private func joiningCompounds(_ words: [String]) -> [String] {
        guard !compounds.isEmpty else { return words }
        var result: [String] = []
        var index = 0
        while index < words.count {
            if let size = [3, 2].first(where: { index + $0 <= words.count && compounds.contains(words[index..<(index + $0)].joined()) }) {
                result.append(words[index..<(index + size)].joined())
                index += size
            } else {
                result.append(words[index])
                index += 1
            }
        }
        return result
    }

    public func parse(_ transcript: String) -> Command? {
        let heard = joiningCompounds(heardWords(transcript))
        if let number = pickNumber(in: heard) {
            return Command(verb: .pick, query: number, raw: transcript)
        }
        let words = commandWords(heard)
        guard !words.isEmpty else { return nil }
        if words.contains("tab"), !newTabMarkers.isDisjoint(with: words) {
            let wanted = words.filter { !newTabNoise.contains($0) && !browserWords.contains($0) }
            return Command(verb: .newTab, query: joined(wanted), kinds: [.tab], raw: transcript)
        }

        let lead = verbLeads.first { words.starts(with: $0.words) }
        let verb = lead?.verb ?? .open
        let target = Array(words.dropFirst(lead?.words.count ?? 0))
        return command(verb, target: target, raw: transcript)
    }

    private static func targetWords(_ text: String) -> [String] {
        replacing(looseSpellings, in: normalizedWords(text)).filter { !fillerWords.contains($0) }
    }

    private func pickNumber(in heard: [String]) -> String? {
        let words = heard.filter { !pickLeadWords.contains($0) }
        guard words.count == 1 else { return nil }
        return pickNumbers[words[0]]
    }

    private func command(_ verb: Verb, target: [String], raw: String) -> Command {
        switch verb {
        case .undo:
            return Command(verb: .undo, query: "", raw: raw)
        case .save, .run:
            // Workspace and routine names are free text: "in" or "tab" inside one is part of the name.
            return Command(verb: verb, query: joined(target), raw: raw)
        case .closeDuplicates:
            return Command(verb: verb, query: joined(withoutKindWords(target)), kinds: [.tab], raw: raw)
        case .restore:
            return Command(verb: verb, query: joined(withoutKindWords(target)), kinds: [.workspace], raw: raw)
        case .newTab:
            return Command(verb: .newTab, query: joined(target), kinds: [.tab], raw: raw)
        case .open, .close, .paste, .hide, .pick, .quit:
            return describedCommand(verb, target: target, raw: raw)
        }
    }

    private func describedCommand(_ verb: Verb, target: [String], raw: String) -> Command {
        var kinds = Set(target.flatMap { kindWords[$0] ?? [] })
        if verb == .paste && kinds.isEmpty { kinds = [.clip] }
        if verb == .quit && kinds.isEmpty { kinds = [.app] }
        var named = withoutKindWords(target)
        if !folderWords.isDisjoint(with: target) {
            // In "the project directory", "project" is the folder's name, not a kind of thing.
            kinds = [.file]
            named = target.filter { !folderWords.contains($0) && (kindWords[$0] == nil || looseKindWords.contains($0)) }
        }
        while let last = named.last, trailingNoise.contains(last) { named.removeLast() }
        let (description, owner) = splitOwner(named)
        if verb == .open, kinds == [.tab], owner.isEmpty, (description.isEmpty || description.allSatisfy(browserWords.contains)) {
            return Command(verb: .newTab, query: "", kinds: [.tab], raw: raw)
        }
        return Command(
            verb: verb,
            query: joined(description),
            kinds: kinds,
            owner: owner.isEmpty ? nil : joined(owner),
            raw: raw
        )
    }

    private func withoutKindWords(_ words: [String]) -> [String] {
        words.filter { kindWords[$0] == nil }
    }

    /// "link i copied from teams" gives (["link"], ["teams"]).
    private func splitOwner(_ words: [String]) -> (description: [String], owner: [String]) {
        var rest: [String] = []
        for word in words {
            if word == "copied" {
                if rest.last == "i" { rest.removeLast() }
            } else {
                rest.append(word)
            }
        }
        // "VS Code with the projects folder": the thing wanted comes after "with", its app before.
        if let with = rest.firstIndex(of: "with") {
            let before = Array(rest[..<with])
            let after = Array(rest[(with + 1)...])
            if before.isEmpty || after.isEmpty { return (before + after, []) }
            return (after, before)
        }
        guard let marker = rest.lastIndex(where: ownerMarkers.contains), marker < rest.count - 1 else {
            return (rest, [])
        }
        return (Array(rest[..<marker]), Array(rest[(marker + 1)...]))
    }

    private func joined(_ words: [String]) -> String {
        replacing(aliases, in: words).joined(separator: " ")
    }
}
