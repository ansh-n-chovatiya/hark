import Foundation

/// A top match below this is never acted on unasked.
let clearScore = 0.65
/// The top match must beat the runner-up by at least this much to act unasked.
let clearMargin = 0.12

private let exactWordCredit = 1.0
private let wordPrefixCredit = 0.85
private let wordSuffixCredit = 0.6
private let insideWordCredit = 0.5
private let subsequenceCredit = 0.35
private let nearWordCredit = 0.75
private let minimumSubsequenceLength = 2

private let ownerFieldWeight = 0.85
private let detailFieldWeight = 0.8

private let titleCoverageShare = 0.1
private let ownerMismatchFactor = 0.4
private let recencyShare = 0.03
private let recencyHalfLifeSeconds = 3600.0
private let kindOnlyScore = 0.5
private let longestWeighedWord = 8

public func rank(_ command: Command, in items: [Item], now: Date) -> [Match] {
    let allowed = kindMask(command.kinds)
    let query = SearchWords(command.query)
    let owner = SearchWords(command.owner ?? "")
    defer {
        query.release()
        owner.release()
    }

    var tally = Tally(items, query: query, owner: owner, allowed: allowed)
    if !owner.isEmpty && !tally.ownerSeen {
        // No item belongs to that owner, so "in X" was part of the description ("sign in page").
        let merged = SearchWords(command.query + " " + (command.owner ?? ""))
        defer { merged.release() }
        tally = Tally(items, query: merged, owner: SearchWords(""), allowed: allowed)
        tally.creditAbbreviations(items, query: merged)
        return tally.matches(items, now: now)
    }
    tally.creditAbbreviations(items, query: query)
    return tally.matches(items, now: now)
}

public func isClear(_ matches: [Match]) -> Bool {
    guard let top = matches.first, top.score >= clearScore else { return false }
    guard matches.count > 1 else { return true }
    return top.score - matches[1].score >= clearMargin
}

/// When several matches are close, the one a person would obviously mean, or nil if it is a real
/// toss-up. Saying a thing's whole name means that thing, saying an app's name means the app and
/// not one of its windows or tabs, and several copies of the same thing are not worth a question.
public func obviousChoice(among matches: [Match], kinds: Set<ItemKind>, query: String = "") -> Item? {
    guard let top = matches.first, top.score >= clearScore else { return nil }
    let rivals = matches.prefix { top.score - $0.score < clearMargin }

    // "code" names the app called Code, not "Claude Code URL Handler" or "Codex".
    let wanted = normalizedWords(query)
    if !wanted.isEmpty {
        let named = rivals.filter { normalizedWords($0.item.title) == wanted }
        if named.count == 1 { return named[0].item }
    }

    if kinds.isEmpty {
        let apps = rivals.filter { $0.item.kind == .app }
        if apps.count == 1 { return apps[0].item }
    }
    // Two folders or files with one name: the one nearer the top of the user's folders is the
    // one people mean, not a copy buried inside another project.
    if rivals.allSatisfy({ $0.item.kind == .file && $0.item.title == top.item.title }) {
        return rivals.map(\.item).min { depth(of: $0) < depth(of: $1) }
    }
    let first = top.item
    let allAlike = rivals.allSatisfy {
        $0.item.kind == first.kind && $0.item.title == first.title
            && $0.item.detail == first.detail && $0.item.owner == first.owner
    }
    return allAlike ? first : nil
}

private func depth(of item: Item) -> Int {
    item.payload["path"]?.split(separator: "/").count ?? .max
}

/// Words held as C strings so the per-item search runs in libc rather than in Swift string code.
private struct SearchWords {
    let pointers: [UnsafeMutablePointer<CChar>]
    let lengths: [Int]
    let weights: [Double]
    let totalWeight: Double

    init(_ text: String) {
        let words = normalizedWords(text)
        pointers = words.map { strdup($0)! }
        lengths = words.map(\.utf8.count)
        weights = lengths.map { Double(min($0, longestWeighedWord)) }
        totalWeight = weights.reduce(0, +)
    }

    var isEmpty: Bool { pointers.isEmpty }

    func release() {
        pointers.forEach { free($0) }
    }
}

/// Per-item sums, kept apart from the final score so a second, slower search can add to them.
private struct Tally {
    private static let excluded = -1.0

    private var matchedWeight: [Double]
    private var titleBytes: [Int]
    private var ownerCoverage: [Double]
    private var wordSeen: [Bool]
    private let hasQuery: Bool
    private let hasOwner: Bool
    private let totalWeight: Double
    private(set) var ownerSeen = false

    init(_ items: [Item], query: SearchWords, owner: SearchWords, allowed: UInt8) {
        matchedWeight = Array(repeating: Tally.excluded, count: items.count)
        titleBytes = Array(repeating: 0, count: items.count)
        ownerCoverage = Array(repeating: 1, count: items.count)
        wordSeen = Array(repeating: false, count: query.pointers.count)
        hasQuery = !query.isEmpty
        hasOwner = !owner.isEmpty
        totalWeight = query.totalWeight

        for index in items.indices where allowed & kindBit(items[index].kind) != 0 {
            let item = items[index]
            matchedWeight[index] = 0
            if hasOwner {
                ownerCoverage[index] = coverage(of: owner, inOwnerOf: item)
                if ownerCoverage[index] > 0 { ownerSeen = true }
            }
            if hasQuery { tallyQuery(query, item: item, at: index) }
        }
    }

    private mutating func tallyQuery(_ query: SearchWords, item: Item, at index: Int) {
        var matched = 0.0
        var bytes = 0
        item.title.withCString { title in
            item.detail.withCString { detail in
                item.owner.withCString { owner in
                    for word in query.pointers.indices {
                        let pointer = query.pointers[word]
                        let length = query.lengths[word]
                        var best = credit(pointer, length, in: title)
                        if best > 0 { bytes += length }
                        if best < exactWordCredit {
                            best = max(best, ownerFieldWeight * credit(pointer, length, in: owner))
                            best = max(best, detailFieldWeight * credit(pointer, length, in: detail))
                        }
                        if best > 0 { wordSeen[word] = true }
                        matched += query.weights[word] * best
                    }
                }
            }
        }
        matchedWeight[index] = matched
        titleBytes[index] = bytes
    }

    /// A word that is part of no item at all is probably a misheard name ("varp" for "warp") or an
    /// abbreviation ("be" for "backend"), so only those words pay for the slower searches.
    mutating func creditAbbreviations(_ items: [Item], query: SearchWords) {
        let unseen = wordSeen.indices.filter { !wordSeen[$0] && query.lengths[$0] >= minimumSubsequenceLength }
        guard !unseen.isEmpty else { return }
        for index in items.indices where matchedWeight[index] != Tally.excluded {
            let item = items[index]
            item.title.withCString { title in
                item.owner.withCString { owner in
                    for word in unseen {
                        let pointer = query.pointers[word]
                        let length = query.lengths[word]
                        if isNearAWord(pointer, length, in: title) || isNearAWord(pointer, length, in: owner) {
                            matchedWeight[index] += query.weights[word] * nearWordCredit
                        } else if isSubsequenceOfAWord(pointer, in: title) {
                            matchedWeight[index] += query.weights[word] * subsequenceCredit
                        }
                    }
                }
            }
        }
    }

    func matches(_ items: [Item], now: Date) -> [Match] {
        var scores = [Double](repeating: 0, count: items.count)
        var order: [UInt64] = []
        for index in items.indices where matchedWeight[index] != Tally.excluded {
            let relevance = relevance(of: items[index], at: index)
            guard relevance > 0 else { continue }
            let ownerFactor = ownerMismatchFactor + (1 - ownerMismatchFactor) * ownerCoverage[index]
            let recent = recency(items[index].lastUsed, now: now)
            scores[index] = min(1, relevance * ownerFactor * (1 - recencyShare) + recencyShare * recent)
            order.append(sortKey(score: scores[index], index: index))
        }
        order.sort()
        return order.map { key in
            let index = Int(key & 0xFFFF_FFFF)
            return Match(item: items[index], score: scores[index])
        }
    }

    private func relevance(of item: Item, at index: Int) -> Double {
        guard hasQuery else {
            return hasOwner ? (ownerCoverage[index] > 0 ? 1 : 0) : kindOnlyScore
        }
        guard matchedWeight[index] > 0 else { return 0 }
        let titleCoverage = min(1, Double(titleBytes[index]) / Double(max(1, item.title.utf8.count)))
        return matchedWeight[index] / totalWeight * (1 - titleCoverageShare + titleCoverageShare * titleCoverage)
    }
}

/// Sorts ascending into best score first, then original order. Integers sort far faster than tuples here.
private func sortKey(score: Double, index: Int) -> UInt64 {
    let rank = UInt64((1 - score) * Double(UInt32.max))
    return rank << 32 | UInt64(index)
}

private func coverage(of owner: SearchWords, inOwnerOf item: Item) -> Double {
    item.owner.withCString { field in
        var matched = 0.0
        for index in owner.pointers.indices {
            matched += owner.weights[index] * credit(owner.pointers[index], owner.lengths[index], in: field)
        }
        return matched / owner.totalWeight
    }
}

/// How well `word` occurs in `field`: as a whole word, the start of one, the end of one, or inside one.
private func credit(_ word: UnsafePointer<CChar>, _ length: Int, in field: UnsafePointer<CChar>) -> Double {
    var best = 0.0
    var from = field
    while let hit = strcasestr(from, word) {
        let startsWord = hit == field || !isWordByte(hit[-1])
        let endsWord = !isWordByte(hit[length])
        if startsWord && endsWord { return exactWordCredit }
        best = max(best, startsWord ? wordPrefixCredit : endsWord ? wordSuffixCredit : insideWordCredit)
        from = UnsafePointer(hit) + 1
    }
    return best
}

/// "bknd" matches "backend": same first letter, remaining letters in order inside that one word.
private func isSubsequenceOfAWord(_ word: UnsafePointer<CChar>, in field: UnsafePointer<CChar>) -> Bool {
    var cursor = field
    var atWordStart = true
    while cursor.pointee != 0 {
        if atWordStart && lowered(cursor.pointee) == word.pointee {
            var wanted = word
            var letter = cursor
            while isWordByte(letter.pointee) && wanted.pointee != 0 {
                if lowered(letter.pointee) == wanted.pointee { wanted += 1 }
                letter += 1
            }
            if wanted.pointee == 0 { return true }
        }
        atWordStart = !isWordByte(cursor.pointee)
        cursor += 1
    }
    return false
}

/// A misheard name is usually a letter or two off, so short words get no slack and longer ones a little.
private func allowedEdits(forLength length: Int) -> Int {
    length < 4 ? 0 : length < 6 ? 1 : 2
}

private func isNearAWord(_ word: UnsafePointer<CChar>, _ length: Int, in field: UnsafePointer<CChar>) -> Bool {
    let edits = allowedEdits(forLength: length)
    guard edits > 0 else { return false }
    let heard = UnsafeBufferPointer(start: word, count: length)
    var cursor = field
    while cursor.pointee != 0 {
        guard isWordByte(cursor.pointee) else {
            cursor += 1
            continue
        }
        var end = cursor
        while isWordByte(end.pointee) { end += 1 }
        let candidate = UnsafeBufferPointer(start: cursor, count: end - cursor)
        if abs(candidate.count - length) <= edits, editDistance(heard, candidate) <= edits { return true }
        cursor = end
    }
    return false
}

private func editDistance(_ heard: UnsafeBufferPointer<CChar>, _ candidate: UnsafeBufferPointer<CChar>) -> Int {
    var previous = Array(0...candidate.count)
    var current = previous
    for row in 1...heard.count {
        current[0] = row
        for column in 1...candidate.count {
            let cost = heard[row - 1] == lowered(candidate[column - 1]) ? 0 : 1
            current[column] = min(previous[column] + 1, current[column - 1] + 1, previous[column - 1] + cost)
        }
        swap(&previous, &current)
    }
    return previous[candidate.count]
}

private func isWordByte(_ byte: CChar) -> Bool {
    // Negative bytes are UTF-8 parts of non-ASCII letters.
    byte < 0 || (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
}

private func lowered(_ byte: CChar) -> CChar {
    byte >= 65 && byte <= 90 ? byte + 32 : byte
}

private func recency(_ lastUsed: Date?, now: Date) -> Double {
    guard let lastUsed else { return 0 }
    let age = max(0, now.timeIntervalSince(lastUsed))
    return recencyHalfLifeSeconds / (recencyHalfLifeSeconds + age)
}

private func kindBit(_ kind: ItemKind) -> UInt8 {
    switch kind {
    case .app: 1
    case .window: 2
    case .tab: 4
    case .file: 8
    case .clip: 16
    case .workspace: 32
    case .routine: 64
    }
}

private func kindMask(_ kinds: Set<ItemKind>) -> UInt8 {
    kinds.isEmpty ? .max : kinds.reduce(0) { $0 | kindBit($1) }
}
