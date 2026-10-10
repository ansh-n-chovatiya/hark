import CryptoKit
import Foundation
import Testing
@testable import HarkCore

private func temporaryClipFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "hark-tests-\(UUID().uuidString)/clips.sqlite")
}

private func rawBytes(inFolderOf url: URL) throws -> Data {
    let folder = url.deletingLastPathComponent()
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .reduce(into: Data()) { bytes, file in bytes.append(try Data(contentsOf: file)) }
}

@Test func clipsSurviveClosingAndReopening() throws {
    let url = temporaryClipFile()
    let key = SymmetricKey(size: .bits256)
    let first = Date(timeIntervalSinceReferenceDate: 800_000_000.25)
    let second = first.addingTimeInterval(60)

    do {
        let store = try ClipStore(url: url, key: key, limit: 100)
        store.add(text: "https://example.com/first", source: "Google Chrome", at: first)
        store.add(text: "second copy\nwith two lines", source: "Microsoft Teams", at: second)
        store.flush()
    }

    let reopened = try ClipStore(url: url, key: key, limit: 100)
    let clips = reopened.all()
    #expect(clips.map(\.text) == ["second copy\nwith two lines", "https://example.com/first"])
    #expect(clips.map(\.source) == ["Microsoft Teams", "Google Chrome"])
    #expect(clips.map(\.at) == [second, first])

    reopened.add(text: "third", source: "Warp", at: second.addingTimeInterval(60))
    #expect(Set(reopened.all().map(\.id)).count == 3)
}

@Test func clipEqualToTheNewestIsSkipped() throws {
    let store = try ClipStore(url: temporaryClipFile(), key: SymmetricKey(size: .bits256), limit: 100)
    let now = Date()
    store.add(text: "alpha", source: "Warp", at: now)
    store.add(text: "alpha", source: "Google Chrome", at: now.addingTimeInterval(1))
    #expect(store.all().count == 1)
    #expect(store.all().first?.source == "Warp")

    store.add(text: "beta", source: "Warp", at: now.addingTimeInterval(2))
    store.add(text: "alpha", source: "Warp", at: now.addingTimeInterval(3))
    #expect(store.all().map(\.text) == ["alpha", "beta", "alpha"])
}

@Test func clipTrimmingKeepsTheNewestLimit() throws {
    let url = temporaryClipFile()
    let key = SymmetricKey(size: .bits256)
    let start = Date()

    do {
        let store = try ClipStore(url: url, key: key, limit: 3)
        for index in 1...10 {
            store.add(text: "clip \(index)", source: "Warp", at: start.addingTimeInterval(Double(index)))
        }
        #expect(store.all().map(\.text) == ["clip 10", "clip 9", "clip 8"])
        store.flush()
    }

    let roomy = try ClipStore(url: url, key: key, limit: 100)
    #expect(roomy.all().map(\.text) == ["clip 10", "clip 9", "clip 8"])
}

@Test func clipStoreWithWrongKeyThrowsAndKeepsTheFile() throws {
    let url = temporaryClipFile()
    let key = SymmetricKey(size: .bits256)

    do {
        let store = try ClipStore(url: url, key: key, limit: 100)
        store.add(text: "kept safe", source: "Warp", at: Date())
        store.flush()
    }

    #expect(throws: ClipStoreError.wrongKey) {
        try ClipStore(url: url, key: SymmetricKey(size: .bits256), limit: 100)
    }

    let reopened = try ClipStore(url: url, key: key, limit: 100)
    #expect(reopened.all().map(\.text) == ["kept safe"])
}

@Test func clipFileDoesNotContainPlaintext() throws {
    let url = temporaryClipFile()
    let secret = "hark-plaintext-canary-4f9a2c"
    let store = try ClipStore(url: url, key: SymmetricKey(size: .bits256), limit: 100)
    store.add(text: "token \(secret) end", source: "Warp", at: Date())
    store.flush()

    let whileOpen = try rawBytes(inFolderOf: url)
    #expect(!whileOpen.isEmpty)
    #expect(whileOpen.range(of: Data(secret.utf8)) == nil)
    #expect(whileOpen.range(of: Data("Warp".utf8)) != nil)
}

@Test func loadingFiveThousandClipsIsFast() throws {
    let url = temporaryClipFile()
    let key = SymmetricKey(size: .bits256)
    let start = Date()

    do {
        let store = try ClipStore(url: url, key: key, limit: 5000)
        for index in 0..<5000 {
            store.add(
                text: "clip number \(index) https://example.com/path/\(index)?query=value",
                source: "Google Chrome",
                at: start.addingTimeInterval(Double(index)))
        }
        store.flush()
    }

    let clock = ContinuousClock()
    var loaded: ClipStore?
    let elapsed = try clock.measure { loaded = try ClipStore(url: url, key: key, limit: 5000) }
    let milliseconds = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
    print("ClipStore loaded 5000 entries in \(String(format: "%.1f", milliseconds)) ms")
    #expect(loaded?.all().count == 5000)
    #expect(elapsed < .milliseconds(200))
}

@Test func clipItemsDescribeEachClip() throws {
    let store = try ClipStore(url: temporaryClipFile(), key: SymmetricKey(size: .bits256), limit: 100)
    let now = Date()
    let copiedAt = now.addingTimeInterval(-3600)
    let long = "  first line\n\tsecond   line " + String(repeating: "x", count: 300)
    store.add(text: long, source: "Microsoft Teams", at: copiedAt)

    let items = store.asItems(now: now)
    #expect(items.count == 1)
    let item = try #require(items.first)
    #expect(item.kind == .clip)
    #expect(item.title.count == 120)
    #expect(item.title.hasPrefix("first line second line xxx"))
    #expect(!item.title.contains("\n"))
    #expect(item.owner == "Microsoft Teams")
    #expect(item.lastUsed == copiedAt)
    #expect(item.detail == RelativeDateTimeFormatter().localizedString(for: copiedAt, relativeTo: now))
    #expect(!item.detail.isEmpty)
}

@Test func clipTitleIsCappedAndNeverEndsInASpace() {
    #expect(ClipStore.title(for: "short") == "short")
    #expect(ClipStore.title(for: " \n ") == "")
    let spaced = String(repeating: "a", count: 119) + " b"
    #expect(ClipStore.title(for: spaced) == String(repeating: "a", count: 119))
}
