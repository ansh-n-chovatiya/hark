import Foundation

/// "Open the budget spreadsheet I worked on Tuesday", "find my contract pdf from last week": a file found by words in its
/// name, its kind and when it was last used. Only names, kinds and dates are looked at, never what is inside a file.
public struct DocumentQuery: Equatable, Sendable {
    public var nameWords: [String]
    /// A uniform type identifier for the kind of file ("public.spreadsheet"), when a kind was said.
    public var kind: String?
    public var since: Date?
    public var until: Date?

    private static let kinds: [String: String] = [
        "spreadsheet": "public.spreadsheet", "spreadsheets": "public.spreadsheet", "pdf": "com.adobe.pdf",
        "presentation": "public.presentation", "slides": "public.presentation", "deck": "public.presentation",
        "image": "public.image", "picture": "public.image", "photo": "public.image", "screenshot": "public.image",
        "document": "public.composite-content", "doc": "public.composite-content", "video": "public.movie",
        "recording": "public.audiovisual-content", "audio": "public.audio", "note": "public.text", "text": "public.text",
    ]
    private static let noise: Set<String> = [
        "open", "find", "show", "get", "me", "my", "the", "a", "an", "i", "that", "worked", "on", "from", "last", "week",
        "yesterday", "today", "this", "month", "morning", "file", "latest", "recent", "recently", "was", "working", "edited",
        "opened", "used", "named", "called", "for", "of", "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday", "earlier", "ago", "days", "day", "two", "three",
    ]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    public static func parse(_ transcript: String, now: Date = Date(), calendar: Calendar = .current) -> DocumentQuery? {
        let words = normalizedWords(transcript)
        guard words.count >= 3, words.count <= 14, ["open", "find", "show", "get"].contains(words.first ?? "") else { return nil }
        // Only when a date is said; a plain "open the budget" belongs to the other rules.
        guard let range = dateRange(words, now: now, calendar: calendar) else { return nil }
        let kind = words.compactMap { kinds[$0] }.first
        let name = words.filter { !noise.contains($0) && kinds[$0] == nil }
        guard !name.isEmpty || kind != nil else { return nil }
        return DocumentQuery(nameWords: name, kind: kind, since: range.start, until: range.end)
    }

    private static func dateRange(_ words: [String], now: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        let text = words.joined(separator: " ")
        if text.contains("yesterday") { return (day(-1), today) }
        if text.contains("last week") { return (day(-7), now) }
        if text.contains("last month") { return (day(-31), now) }
        if text.contains("this morning") || words.contains("today") { return (today, now) }
        if let name = words.first(where: { weekdays.contains($0) }), let target = weekdays.firstIndex(of: name) {
            let current = calendar.component(.weekday, from: now) - 1
            let back = (current - target + 7) % 7
            let offset = back == 0 ? 7 : back
            return (day(-offset), day(-offset + 1))
        }
        if text.contains("days ago"), let number = words.compactMap({ Int($0) }).first { return (day(-number), day(-number + 1)) }
        return nil
    }

    /// The Spotlight query text for this search.
    public var spotlight: String {
        var parts = nameWords.map { "kMDItemFSName == \"*\($0.replacingOccurrences(of: "\"", with: ""))*\"cd" }
        if let kind { parts.append("kMDItemContentTypeTree == \"\(kind)\"") }
        let format = ISO8601DateFormatter()
        if let since { parts.append("kMDItemLastUsedDate >= $time.iso(\(format.string(from: since)))") }
        if let until { parts.append("kMDItemLastUsedDate < $time.iso(\(format.string(from: until)))") }
        return parts.joined(separator: " && ")
    }
}
