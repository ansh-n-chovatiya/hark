import AppKit
import CoreServices
import HarkCore
import UniformTypeIdentifiers

public actor FilesSource: ItemSource {
    public nonisolated let kinds: Set<ItemKind> = [.file]

    private static let candidateLimit = 200

    private let roots: [String]
    private var index = FileIndex()
    private var watcher: FolderWatcher?
    private var isWalking = false
    private var changedDuringWalk = false
    private var walkMs = 0.0

    public init(folders: [String]) {
        roots = FileIndex.searchRoots(folders)
    }

    /// The walk runs at launch only; after that the folder watcher keeps the index current, so a
    /// refresh on key down costs nothing.
    public func refresh() async {
        guard watcher == nil, !roots.isEmpty else { return }
        watcher = FolderWatcher(roots: roots) { [weak self] in
            Task { await self?.reindex() }
        }
        await reindex()
    }

    public func items(for command: Command) async -> [Item] {
        guard command.kinds.isEmpty || command.kinds.contains(.file) else { return [] }
        // The matcher folds the owner words into the query when no item has that owner, and
        // files have none, so they must count here too.
        let words = searchWords(command.query + " " + (command.owner ?? ""))
        return index.candidates(for: words, limit: Self.candidateLimit).map(index.item)
    }

    public func perform(_ verb: Verb, on item: Item) async throws -> UndoStep? {
        guard verb == .open else { throw SourceError.unsupported(verb, item.kind) }
        var isFolder: ObjCBool = false
        guard let path = item.payload["path"], FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else {
            throw SourceError.gone(item.title)
        }
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if isFolder.boolValue || Self.isTextOrCode(url), let editor = await Self.editor() {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: configuration)
        } else {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
        }
        return nil
    }

    public func stats() -> (count: Int, walkMs: Double) {
        (index.count, walkMs)
    }

    private func reindex() async {
        guard !isWalking else {
            changedDuringWalk = true
            return
        }
        isWalking = true
        repeat {
            changedDuringWalk = false
            let roots = self.roots
            let started = ContinuousClock.now
            index = await Task.detached { FileIndex.walk(roots) }.value
            let elapsed = ContinuousClock.now - started
            walkMs = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        } while changedDuringWalk
        isWalking = false
    }

    /// The editor for a project folder, or for code and text when the user has not set an app of their own for
    /// that kind of file.
    @MainActor private static func editor() -> URL? {
        AppNames.preferredEditor()?.url
    }

    // macOS files these extensions as MPEG-2 video.
    private static let typeScriptExtensions: Set<String> = ["ts", "mts", "cts"]

    private static func isTextOrCode(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if typeScriptExtensions.contains(fileExtension) { return true }
        if let type = UTType(filenameExtension: fileExtension), !type.isDynamic {
            return type.conforms(to: .text)
        }
        // No known type (Dockerfile, .env, .tsx, .toml): text files hold no zero bytes.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        return !head.contains(0)
    }
}

/// Same word rule as the matcher's `normalizedWords`, which is not visible outside HarkCore.
private func searchWords(_ text: String) -> [String] {
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

/// Every name sits in one lowercased byte buffer as "name<tab>folder<newline>", so a query word
/// is found by a single libc scan over the buffer instead of one string search per file.
private struct FileIndex: Sendable {
    private static let skippedFolders: Set<String> = [
        "node_modules", ".git", ".build", "build", "dist", ".venv", "graphify-out",
    ]
    private static let tab = UInt8(ascii: "\t")
    private static let newline = UInt8(ascii: "\n")

    // Mirrors the matcher's weights so the best candidates here are the ones it will rank highest.
    private static let folderCredit: Float = 0.8
    private static let abbreviationCredit: Float = 0.35
    private static let longestWeighedWord = 8

    private var paths: [String] = []
    private var modified: [Date] = []
    private var text: [UInt8] = [0]
    private var recordStarts: [Int] = [0]
    private var nameEnds: [Int] = []

    var count: Int { paths.count }

    static func searchRoots(_ folders: [String]) -> [String] {
        let expanded = Set(folders.map { folder in
            guard let resolved = realpath(NSString(string: folder).expandingTildeInPath, nil) else {
                return URL(fileURLWithPath: NSString(string: folder).expandingTildeInPath).standardizedFileURL.path
            }
            defer { free(resolved) }
            return String(cString: resolved)
        })
        return expanded.filter { root in !expanded.contains { $0 != root && root.hasPrefix($0 + "/") } }.sorted()
    }

    static func isSkipped(folderName: String) -> Bool {
        folderName.hasPrefix(".") || skippedFolders.contains(folderName)
    }

    static func walk(_ roots: [String]) -> FileIndex {
        var index = FileIndex()
        index.text.removeAll()
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        for root in roots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard let entries = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: keys) else {
                continue
            }
            for case let url as URL in entries {
                let name = url.lastPathComponent
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true, isSkipped(folderName: name) {
                    entries.skipDescendants()
                    continue
                }
                if name == ".DS_Store" { continue }
                index.append(path: url.path, name: name, modified: values?.contentModificationDate ?? .distantPast)
            }
        }
        index.text.append(0)
        return index
    }

    private mutating func append(path: String, name: String, modified date: Date) {
        paths.append(path)
        modified.append(date)
        appendLowered(name)
        nameEnds.append(text.count)
        text.append(Self.tab)
        appendLowered(Self.shortFolder(of: path))
        text.append(Self.newline)
        recordStarts.append(text.count)
    }

    private mutating func appendLowered(_ field: String) {
        for byte in field.lowercased().utf8 {
            text.append(byte == Self.tab || byte == Self.newline || byte == 0 ? UInt8(ascii: " ") : byte)
        }
    }

    private static func shortFolder(of path: String) -> String {
        path.split(separator: "/").dropLast().suffix(2).joined(separator: "/")
    }

    func item(_ record: Int) -> Item {
        let path = paths[record]
        return Item(
            id: "file:\(path)",
            kind: .file,
            title: URL(fileURLWithPath: path).lastPathComponent,
            detail: Self.shortFolder(of: path),
            lastUsed: modified[record],
            payload: ["path": path]
        )
    }

    func candidates(for words: [String], limit: Int) -> [Int] {
        guard !words.isEmpty else {
            return Array(paths.indices.sorted { modified[$0] > modified[$1] }.prefix(limit))
        }
        var scores = [Float](repeating: 0, count: count)
        var unseen: [String] = []
        for word in words where !credit(word, into: &scores) && word.utf8.count >= 2 {
            unseen.append(word)
        }
        for word in unseen {
            creditAbbreviation(word, into: &scores)
        }
        let hits = scores.indices.filter { scores[$0] > 0 }
        guard hits.count > limit else { return hits }
        return Array(hits.sorted { isBetter($0, than: $1, scores: scores) }.prefix(limit))
    }

    private func isBetter(_ left: Int, than right: Int, scores: [Float]) -> Bool {
        if scores[left] != scores[right] { return scores[left] > scores[right] }
        let leftLength = nameEnds[left] - recordStarts[left]
        let rightLength = nameEnds[right] - recordStarts[right]
        if leftLength != rightLength { return leftLength < rightLength }
        return modified[left] > modified[right]
    }

    private static func weight(of word: String) -> Float {
        Float(min(word.utf8.count, longestWeighedWord))
    }

    /// Adds the word's weight to every record that contains it; false when none does.
    private func credit(_ word: String, into scores: inout [Float]) -> Bool {
        let weight = Self.weight(of: word)
        var found = false
        text.withUnsafeBufferPointer { buffer in
            guard let base = UnsafeRawPointer(buffer.baseAddress)?.assumingMemoryBound(to: CChar.self) else { return }
            word.withCString { needle in
                var cursor = base
                var record = 0
                while let hit = strstr(cursor, needle) {
                    let offset = base.distance(to: UnsafePointer(hit))
                    record = self.record(containing: offset, from: record)
                    // The name comes first in a record, so a first hit past it means folder only.
                    scores[record] += offset < nameEnds[record] ? weight : weight * Self.folderCredit
                    found = true
                    cursor = base + recordStarts[record + 1]
                }
            }
        }
        return found
    }

    private func record(containing offset: Int, from first: Int) -> Int {
        var low = first
        var high = count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if recordStarts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// "bknd" reaches "backend": same first letter, the rest in order inside that one word.
    private func creditAbbreviation(_ word: String, into scores: inout [Float]) {
        let letters = Array(word.utf8)
        let credit = Self.weight(of: word) * Self.abbreviationCredit
        for record in 0..<count {
            var position = recordStarts[record]
            let end = nameEnds[record]
            var atWordStart = true
            while position < end {
                if atWordStart && text[position] == letters[0] && isAbbreviation(letters, at: position, end: end) {
                    scores[record] += credit
                    break
                }
                atWordStart = !Self.isWordByte(text[position])
                position += 1
            }
        }
    }

    private func isAbbreviation(_ letters: [UInt8], at start: Int, end: Int) -> Bool {
        var wanted = 0
        var position = start
        while position < end && wanted < letters.count && Self.isWordByte(text[position]) {
            if text[position] == letters[wanted] { wanted += 1 }
            position += 1
        }
        return wanted == letters.count
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        byte >= 128 || (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 122)
    }
}

/// Calls `onChange` when something changes under the roots, outside the folders the index skips.
private final class FolderWatcher: @unchecked Sendable {
    private final class Listener {
        let roots: [String]
        let onChange: @Sendable () -> Void

        init(roots: [String], onChange: @escaping @Sendable () -> Void) {
            self.roots = roots
            self.onChange = onChange
        }

        func isIndexed(_ path: String) -> Bool {
            guard let root = roots.first(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return true }
            return !path.dropFirst(root.count).split(separator: "/").contains {
                FileIndex.isSkipped(folderName: String($0))
            }
        }
    }

    private static let latencySeconds = 0.3

    private let stream: FSEventStreamRef

    init?(roots: [String], onChange: @escaping @Sendable () -> Void) {
        let listener = Listener(roots: roots, onChange: onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(listener).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Listener>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Listener>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let listener = Unmanaged<Listener>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            if paths.contains(where: listener.isIndexed) { listener.onChange() }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, roots as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latencySeconds,
            FSEventStreamCreateFlags(flags)
        ) else { return nil }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "hark.files.watcher", qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
