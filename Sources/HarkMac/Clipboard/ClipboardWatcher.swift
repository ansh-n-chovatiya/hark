import AppKit
import HarkCore

/// Records every text copy. macOS sends no notice when the clipboard changes, so this polls its
/// change count.
@MainActor public final class ClipboardWatcher {
    private static let interval: TimeInterval = 0.25

    private let store: ClipStore
    private let pasteboard = NSPasteboard.general
    private var lastChange: Int
    private var timer: Timer?

    public init(store: ClipStore) {
        self.store = store
        lastChange = pasteboard.changeCount
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Puts text on the clipboard without recording it as a new copy.
    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChange = pasteboard.changeCount
    }

    var current: String? {
        pasteboard.string(forType: .string)
    }

    private func check() {
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        store.add(text: text, source: source, at: Date())
    }
}
