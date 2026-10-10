import AppKit
import HarkCore

public enum SourceError: LocalizedError, Sendable {
    case unsupported(Verb, ItemKind)
    case gone(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let verb, let kind): "Hark cannot \(verb.rawValue) \(kind.rawValue) items yet."
        case .gone(let title): "\(title) is no longer there."
        }
    }
}

public actor AppsSource: ItemSource {
    public nonisolated let kinds: Set<ItemKind> = [.app]

    private var installed: [Item]?
    private var snapshot: [Item] = []

    public init() {}

    public func refresh() async {
        let installed = self.installed ?? Self.scanInstalled()
        self.installed = installed
        let running = await Self.runningItems()
        let runningPaths = Set(running.compactMap { $0.payload["path"] })
        snapshot = running + installed.filter { !runningPaths.contains($0.payload["path"] ?? "") }
    }

    public func items(for command: Command) async -> [Item] {
        snapshot
    }

    public func perform(_ verb: Verb, on item: Item) async throws -> UndoStep? {
        switch verb {
        case .open:
            guard let path = item.payload["path"] else { throw SourceError.gone(item.title) }
            let previous = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleURL }
            try await Self.bringForward(URL(fileURLWithPath: path))
            guard let previous, previous.path != path else { return nil }
            return UndoStep(summary: "Went back from \(item.title)") { try await Self.bringForward(previous) }
        case .hide:
            guard let app = Self.runningApp(for: item) else { throw SourceError.gone(item.title) }
            app.hide()
            return UndoStep(summary: "Showed \(item.title) again") { app.unhide() }
        case .quit:
            guard let app = Self.runningApp(for: item), let path = item.payload["path"] else {
                throw SourceError.gone(item.title)
            }
            app.terminate()
            await Self.waitUntilGone(app)
            return UndoStep(summary: "Opened \(item.title) again") { try await Self.bringForward(URL(fileURLWithPath: path)) }
        default:
            throw SourceError.unsupported(verb, item.kind)
        }
    }

    /// Starts an app without showing it: no window comes up and the user stays where they are.
    /// An app that is already running is left exactly as it is.
    public func openInBackground(_ item: Item) async throws {
        guard item.payload["pid"] == nil else { return }
        guard let path = item.payload["path"] else { throw SourceError.gone(item.title) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        let app = URL(fileURLWithPath: path)
        if Browser.isChrome(app) { configuration.arguments = Browser.startArguments() }
        let previous = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        let started = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        // The first second is waited for, so the answer is true when it is given. Slower apps
        // (Wispr Flow shows its window a few seconds in) are watched for a while longer without
        // keeping the user waiting.
        await keepHidden(started, returningTo: previous, checks: 6)
        Task { await self.keepHidden(started, returningTo: previous, checks: 40) }
    }

    /// Some apps show a window a moment after starting, whatever they were asked. For a few
    /// seconds each such window is hidden again and the user's own app is put back in front.
    private func keepHidden(
        _ app: NSRunningApplication, returningTo previous: NSRunningApplication?, checks: Int
    ) async {
        for _ in 0..<checks where !app.isTerminated {
            try? await Task.sleep(for: .milliseconds(200))
            if app.isHidden && !app.isActive { continue }
            app.hide()
            if app.isActive, let home = previous?.bundleURL { try? await Self.bringForward(home) }
        }
    }

    // Launch Services activates reliably from a background app; NSRunningApplication.activate
    // is ignored by macOS when the caller is not the active app.
    private static func bringForward(_ app: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if Browser.isChrome(app) { configuration.arguments = Browser.startArguments() }
        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    /// A later step may reopen the same app, which fails while the old copy is still closing.
    private static func waitUntilGone(_ app: NSRunningApplication) async {
        for _ in 0..<30 where !app.isTerminated {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func runningApp(for item: Item) -> NSRunningApplication? {
        guard let text = item.payload["pid"], let pid = pid_t(text) else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    @MainActor private static func runningItems() -> [Item] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let name = app.localizedName, let url = app.bundleURL else {
                return nil
            }
            return Item(
                id: "app:\(app.processIdentifier)",
                kind: .app,
                title: name,
                detail: "Open",
                lastUsed: app.processIdentifier == front ? Date() : nil,
                payload: ["pid": "\(app.processIdentifier)", "path": url.path]
            )
        }
    }

    private static func scanInstalled() -> [Item] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", "\(home)/Applications"]
        return folders.flatMap { folder -> [Item] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            return names.filter { $0.hasSuffix(".app") }.map { name in
                Item(
                    id: "app:\(folder)/\(name)",
                    kind: .app,
                    title: String(name.dropLast(4)),
                    detail: "Not open",
                    payload: ["path": "\(folder)/\(name)"]
                )
            }
        }
    }
}
