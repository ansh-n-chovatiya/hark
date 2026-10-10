/// Puts back names the main recogniser misheard, using a second hearing of the same audio that
/// was told the vocabulary.
///
/// The main transcript is kept word for word except where the second hearing put vocabulary names
/// in a spot where the main one has something that sounds close and is not itself a name:
/// "Go to war." and "Go to Warp" give "Go to Warp.".
func restoreNames(in heard: String, from biased: String, vocabulary: [String]) -> String {
    let names = Set(vocabulary.map(spokenKey))
    let ours = heard.split(separator: " ")
    let theirs = biased.split(separator: " ")
    let ourKeys = ours.map(spokenKey)
    let theirKeys = theirs.map(spokenKey)

    var result: [Substring] = []
    var ourStart = 0
    var theirStart = 0
    let ends = [(ours.count, theirs.count)]
    for (ourEnd, theirEnd) in commonWords(ourKeys, theirKeys) + ends {
        let ourGap = ourStart..<ourEnd
        let theirGap = theirStart..<theirEnd
        let replaced = rangeToReplace(in: ourKeys, ourGap, with: theirKeys[theirGap], names: names)
        result += ours[ourGap.lowerBound..<(replaced?.lowerBound ?? ourGap.upperBound)]
        if let replaced {
            result += theirs[theirGap]
            if let mark = ours[replaced].last?.last, mark.isPunctuation, let last = result.popLast() {
                result.append(Substring(String(last) + String(mark)))
            }
            result += ours[replaced.upperBound..<ourGap.upperBound]
        }
        if ourEnd < ours.count { result.append(ours[ourEnd]) }
        ourStart = ourEnd + 1
        theirStart = theirEnd + 1
    }
    return result.joined(separator: " ")
}

/// Letters and digits only, lowercased, so "Shop-backend," and "shop backend" compare equal
/// once joined.
private func spokenKey(_ text: some StringProtocol) -> String {
    String(text.lowercased().filter { $0.isLetter || $0.isNumber })
}

/// The stretch of our words that their names should take the place of, if any.
private func rangeToReplace(
    in ours: [String], _ gap: Range<Int>, with theirs: ArraySlice<String>, names: Set<String>
) -> Range<Int>? {
    guard !gap.isEmpty, isNames(theirs, names: names) else { return nil }
    let theirSound = theirs.joined()
    // The same name split differently ("pricing engine" for "PricingEngine") takes the vocabulary's
    // spelling, and whatever else we heard around it stays.
    for start in gap {
        var sound = ""
        for end in start..<gap.upperBound {
            sound += ours[end]
            if sound == theirSound { return start..<end + 1 }
            if sound.count >= theirSound.count { break }
        }
    }
    let ourSound = ours[gap].joined()
    // A plural is our word, not a mishearing: "tabs" must not become "tab".
    guard !isNames(ours[gap], names: names), ourSound != theirSound + "s" else { return nil }
    // Half the letters may differ: "work" for "Warp" and "bacon" for "backend" pass, while a
    // name the second hearing put in place of unrelated words does not.
    let distance = editDistance(Array(ourSound), Array(theirSound))
    return distance * 2 <= max(ourSound.count, theirSound.count) ? gap : nil
}

/// True when the words are one or more vocabulary names back to back, each up to three words long.
private func isNames(_ keys: ArraySlice<String>, names: Set<String>) -> Bool {
    guard let first = keys.indices.first else { return false }
    var start = first
    while start < keys.endIndex {
        let longest = min(start + 3, keys.endIndex)
        guard let end = (start + 1...longest).reversed().first(where: { names.contains(keys[start..<$0].joined()) }) else {
            return false
        }
        start = end
    }
    return true
}

/// Index pairs of the longest run of words both transcripts share, in order.
private func commonWords(_ ours: [String], _ theirs: [String]) -> [(Int, Int)] {
    guard !ours.isEmpty, !theirs.isEmpty else { return [] }
    var lengths = Array(repeating: Array(repeating: 0, count: theirs.count + 1), count: ours.count + 1)
    for i in ours.indices.reversed() {
        for j in theirs.indices.reversed() {
            lengths[i][j] = ours[i] == theirs[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
        }
    }
    var pairs: [(Int, Int)] = []
    var i = 0
    var j = 0
    while i < ours.count, j < theirs.count {
        if ours[i] == theirs[j] {
            pairs.append((i, j))
            i += 1
            j += 1
        } else if lengths[i + 1][j] >= lengths[i][j + 1] {
            i += 1
        } else {
            j += 1
        }
    }
    return pairs
}

private func editDistance(_ a: [Character], _ b: [Character]) -> Int {
    var previous = Array(0...b.count)
    for (i, left) in a.enumerated() {
        var current = [i + 1]
        for (j, right) in b.enumerated() {
            current.append(min(previous[j] + (left == right ? 0 : 1), previous[j + 1] + 1, current[j] + 1))
        }
        previous = current
    }
    return previous[b.count]
}
