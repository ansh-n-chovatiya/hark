import Foundation
import HarkCore

public enum Registry {
    public static func sources(config: Config) -> [any ItemSource] {
        [AppsSource(), WindowsSource()] + browserSources() + [FilesSource(folders: config.searchFolders)]
    }

    /// One tab source for each scriptable browser on this Mac.
    public static func browserSources() -> [BrowserTabsSource] {
        Browsers.scriptable.map { BrowserTabsSource(browser: $0) }
    }

    /// Kept apart from `sources` because it starts recording copies, which only the running app
    /// should do.
    @MainActor public static func clipboard(config: Config) throws -> (source: ClipSource, watcher: ClipboardWatcher) {
        let url = Paths.support.appending(path: "clips.sqlite")
        let key = try ClipKey.loadOrCreate()
        let store: ClipStore
        do {
            store = try ClipStore(url: url, key: key, limit: config.clipLimit)
        } catch ClipStoreError.wrongKey {
            // History written under an earlier key cannot be read. It is set aside, not deleted.
            try setAside(url)
            store = try ClipStore(url: url, key: key, limit: config.clipLimit)
        }
        let watcher = ClipboardWatcher(store: store)
        return (ClipSource(store: store, watcher: watcher), watcher)
    }

    private static func setAside(_ database: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: database.path + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let kept = URL(fileURLWithPath: database.path + ".unreadable" + suffix)
            try? FileManager.default.removeItem(at: kept)
            try FileManager.default.moveItem(at: file, to: kept)
        }
    }
}
