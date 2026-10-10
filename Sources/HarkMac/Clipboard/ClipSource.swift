import AppKit
import HarkCore

public actor ClipSource: ItemSource {
    public nonisolated let kinds: Set<ItemKind> = [.clip]

    private let store: ClipStore
    private let watcher: ClipboardWatcher

    public init(store: ClipStore, watcher: ClipboardWatcher) {
        self.store = store
        self.watcher = watcher
    }

    public func refresh() async {}

    public func items(for command: Command) async -> [Item] {
        store.asItems()
    }

    /// The copy before the one now on the clipboard: what "paste" alone means, for when a newer
    /// copy has pushed out the one the user wanted.
    public func previous() -> Item? {
        let items = store.asItems()
        return items.count > 1 ? items[1] : nil
    }

    public func perform(_ verb: Verb, on item: Item) async throws -> UndoStep? {
        guard verb == .paste else { throw SourceError.unsupported(verb, item.kind) }
        guard let id = item.payload["clipID"].flatMap(Int64.init),
              let clip = store.all().first(where: { $0.id == id })
        else { throw SourceError.gone(item.title) }

        let watcher = self.watcher
        let before = await MainActor.run {
            let before = watcher.current
            watcher.write(clip.text)
            Self.pressPaste()
            return before
        }
        guard let before else { return nil }
        return UndoStep(summary: "Put the clipboard back") {
            await MainActor.run { watcher.write(before) }
        }
    }

    @MainActor private static func pressPaste() {
        let vKey: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
