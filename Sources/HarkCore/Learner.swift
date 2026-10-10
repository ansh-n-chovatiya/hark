import Foundation

/// Something Hark noticed that the user can accept with one tap. Accepting only ever adds a name,
/// a saved web page or an open-only routine; it never adds an action.
public struct Suggestion: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case name, page, routine }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    /// For a name: the words that were heard, and what was meant.
    public var said: String?
    public var meant: String?
    /// For a page: the name to say and where it goes.
    public var pageName: String?
    public var address: String?
    /// For a routine: its name, the commands it says, and the pages it needs saved first.
    public var routineName: String?
    public var steps: [String]?
    public var pages: [String: String]?

    public init(
        id: String, kind: Kind, title: String, detail: String, said: String? = nil, meant: String? = nil,
        pageName: String? = nil, address: String? = nil, routineName: String? = nil, steps: [String]? = nil,
        pages: [String: String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.said = said
        self.meant = meant
        self.pageName = pageName
        self.address = address
        self.routineName = routineName
        self.steps = steps
        self.pages = pages
    }
}

/// Something the user asked for that Hark could not do, said more than once.
public struct DeadEnd: Sendable, Equatable {
    public var phrase: String
    public var count: Int
    public var lastSeen: Date
    public var topic: String?

    public init(phrase: String, count: Int, lastSeen: Date, topic: String? = nil) {
        self.phrase = phrase
        self.count = count
        self.lastSeen = lastSeen
        self.topic = topic
    }
}

/// Works out suggestions from what happened, by counting. No model is involved, so the same history
/// always gives the same answer and nothing about it leaves the Mac.
public enum Learner {
    static let pairWindow: TimeInterval = 90
    static let sessionGap: TimeInterval = 30 * 60
    static let sessionStart: TimeInterval = 10 * 60
    static let daysNeeded = 3
    static let mostWordsInACommand = 8

    private static let ignoredApps: Set<String> = [
        "hark", "finder", "loginwindow", "dock", "spotlight", "control center", "notification center",
        "systemuiserver", "universalaccessd", "screencaptureui", "system settings",
    ]

    public static func suggestions(
        history: [Timings], activity: [ActivityEvent], config: Config, calendar: Calendar = .current
    ) -> [Suggestion] {
        names(history: history, config: config)
            + pages(activity: activity, config: config, calendar: calendar)
            + routines(activity: activity, config: config, calendar: calendar)
    }

    // MARK: Misheard words

    private struct Pair { var said: String, meant: String, similarity: Double, count: Int }

    static func names(history: [Timings], config: Config) -> [Suggestion] {
        let ordered = history.sorted { $0.at < $1.at }
        var pairs: [String: Pair] = [:]
        for (index, failed) in ordered.enumerated() where isFailure(failed) {
            guard let fixed = ordered[(index + 1)...].prefix(while: { $0.at.timeIntervalSince(failed.at) <= pairWindow })
                .first(where: { $0.outcome == "done" })
            else { continue }
            let said = normalize(failed.raw), meant = normalize(fixed.raw)
            guard !said.isEmpty, !meant.isEmpty, said != meant,
                  wordCount(said) <= mostWordsInACommand, wordCount(meant) <= mostWordsInACommand
            else { continue }
            let similarity = similarity(said, meant)
            guard similarity >= 0.4 || sharesAWord(said, meant) else { continue }
            let key = said + ">" + meant
            pairs[key, default: Pair(said: said, meant: meant, similarity: similarity, count: 0)].count += 1
        }
        let known = Set(config.aliases.keys.map(normalize))
        return pairs.values
            .filter { ($0.count >= 2 || $0.similarity >= 0.6) && !known.contains($0.said) }
            .sorted { ($0.count, $0.said) > ($1.count, $1.said) }
            .map { pair in
                Suggestion(
                    id: "name:\(pair.said)>\(pair.meant)", kind: .name,
                    title: "When you say \u{201C}\(pair.said)\u{201D}, hear \u{201C}\(pair.meant)\u{201D}",
                    detail: pair.count == 1
                        ? "Hark missed it, then you said it the other way and it worked."
                        : "Hark missed it \(pair.count) times, then you said it the other way and it worked.",
                    said: pair.said, meant: pair.meant)
            }
    }

    private static func isFailure(_ entry: Timings) -> Bool {
        guard entry.outcome == "notUnderstood" || entry.outcome == "failed" else { return false }
        return !isRefusal(entry)
    }

    /// Hark refuses some things on purpose. Those are not mistakes to learn from.
    private static func isRefusal(_ entry: Timings) -> Bool {
        (entry.summary ?? "").localizedCaseInsensitiveContains("does not delete")
    }

    // MARK: Web pages

    static func pages(activity: [ActivityEvent], config: Config, calendar: Calendar) -> [Suggestion] {
        var days: [String: Set<Date>] = [:]
        for event in activity where event.kind == .site && isNameable(host: event.name) {
            days[event.name, default: []].insert(calendar.startOfDay(for: event.at))
        }
        let saved = Set(config.links.values.compactMap { URL(string: $0)?.host()?.lowercased() }.map(stripWWW))
        return days.filter { $0.value.count >= daysNeeded && !saved.contains(stripWWW($0.key)) }
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
            .prefix(5)
            .map { host, dates in
                let name = pageName(forHost: host)
                return Suggestion(
                    id: "page:\(stripWWW(host))", kind: .page,
                    title: "Open \u{201C}\(name)\u{201D} by name",
                    detail: "You were on \(stripWWW(host)) on \(dates.count) different days.",
                    pageName: name, address: "https://\(host)")
            }
    }

    static func pageName(forHost host: String) -> String {
        var labels = stripWWW(host).split(separator: ".").map(String.init)
        if labels.count >= 3, labels.last?.count == 2, ["co", "com", "org", "gov", "ac", "net"].contains(labels[labels.count - 2]) {
            labels.removeLast(2)
        } else if labels.count >= 2 {
            labels.removeLast()
        }
        return labels.joined(separator: " ")
    }

    private static func stripWWW(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    private static func isNameable(host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") || lower.isEmpty { return false }
        // An address of numbers is not something anyone would say.
        return lower.contains(where: \.isLetter)
    }

    // MARK: Repeated chores

    private struct Day { var items: Set<String>; var hour: Int }

    static func routines(activity: [ActivityEvent], config: Config, calendar: Calendar) -> [Suggestion] {
        let events = activity.filter { event in
            event.kind == .site ? isNameable(host: event.name) : !ignoredApps.contains(event.name.lowercased())
        }.sorted { $0.at < $1.at }
        // The first session of each day, and what was opened in its first ten minutes.
        var days: [Date: Day] = [:]
        var firstSession: [Date: Date] = [:]
        var sessionBegan: Date?
        var previous: Date?
        for event in events {
            if let last = previous, event.at.timeIntervalSince(last) <= sessionGap {
                // Same session as the one before.
            } else {
                sessionBegan = event.at
                let day = calendar.startOfDay(for: event.at)
                if firstSession[day] == nil { firstSession[day] = event.at }
            }
            previous = event.at
            guard let began = sessionBegan else { continue }
            let day = calendar.startOfDay(for: began)
            guard firstSession[day] == began, event.at.timeIntervalSince(began) <= sessionStart else { continue }
            var entry = days[day] ?? Day(items: [], hour: calendar.component(.hour, from: began))
            entry.items.insert("\(event.kind.rawValue):\(event.name)")
            days[day] = entry
        }
        guard days.count >= daysNeeded else { return [] }
        var seen: [String: Int] = [:]
        for day in days.values { for item in day.items { seen[item, default: 0] += 1 } }
        let usual = seen.filter { $0.value >= daysNeeded && Double($0.value) / Double(days.count) >= 0.5 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(6).map(\.key)
        guard usual.count >= 2 else { return [] }

        let hours = days.values.map(\.hour).sorted()
        let name = routineName(hour: hours[hours.count / 2], taken: Set(config.routines.map { $0.name.lowercased() }))
        var steps: [String] = []
        var pages: [String: String] = [:]
        for item in usual.sorted() {
            let (kind, value) = (item.prefix(while: { $0 != ":" }), String(item.drop(while: { $0 != ":" }).dropFirst()))
            if kind == "app" {
                steps.append("open \(value)")
            } else {
                let existing = config.links.first { URL(string: $0.value)?.host().map(stripWWW) == stripWWW(value) }?.key
                let page = existing ?? pageName(forHost: value)
                steps.append("open \(page)")
                if existing == nil { pages[page] = "https://\(value)" }
            }
        }
        let already = config.routines.contains { $0.steps.compactMap(\.say) == steps }
        guard !already else { return [] }
        return [Suggestion(
            id: "routine:" + usual.sorted().joined(separator: "+"), kind: .routine,
            title: "Start your day with one word: \u{201C}\(name)\u{201D}",
            detail: "You opened these together at the start of \(days.count) days: "
                + usual.sorted().map { String($0.drop(while: { $0 != ":" }).dropFirst()) }.joined(separator: ", ") + ".",
            routineName: name, steps: steps, pages: pages.isEmpty ? nil : pages)]
    }

    private static func routineName(hour: Int, taken: Set<String>) -> String {
        let base = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        var name = base, number = 2
        while taken.contains(name) { name = "\(base) \(number)"; number += 1 }
        return name
    }

    // MARK: Dead ends

    private static let topics: [(String, [String])] = [
        ("Searching the web", ["search", "google", "look up", "find online"]),
        ("Email", ["email", "mail"]),
        ("Calendar", ["calendar", "meeting", "schedule"]),
        ("Reminders", ["remind"]),
    ]

    public static func deadEnds(history: [Timings]) -> [DeadEnd] {
        var groups: [String: DeadEnd] = [:]
        for entry in history where isFailure(entry) {
            let phrase = normalize(entry.raw)
            guard wordCount(phrase) >= 2 else { continue }
            var group = groups[phrase] ?? DeadEnd(
                phrase: phrase, count: 0, lastSeen: entry.at,
                topic: topics.first { $0.1.contains { phrase.contains($0) } }?.0)
            group.count += 1
            group.lastSeen = max(group.lastSeen, entry.at)
            groups[phrase] = group
        }
        return Array(groups.values.sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }.prefix(10))
    }

    // MARK: Words

    static func normalize(_ text: String) -> String {
        let letters = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    private static func wordCount(_ text: String) -> Int { text.split(separator: " ").count }

    private static func sharesAWord(_ a: String, _ b: String) -> Bool {
        let first = Set(a.split(separator: " ").filter { $0.count >= 4 })
        return b.split(separator: " ").contains { first.contains($0) }
    }

    /// 1 for identical text, 0 for nothing in common, from the number of edits between them.
    static func similarity(_ a: String, _ b: String) -> Double {
        let (x, y) = (Array(a), Array(b))
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var row = Array(0...y.count)
        for i in 1...x.count {
            var diagonal = row[0]
            row[0] = i
            for j in 1...y.count {
                let above = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, diagonal + (x[i - 1] == y[j - 1] ? 0 : 1))
                diagonal = above
            }
        }
        return 1 - Double(row[y.count]) / Double(max(x.count, y.count))
    }
}
