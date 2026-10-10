import AppKit
import Carbon
import HarkCore

public enum ChromeTabsError: LocalizedError, Sendable {
    case automationDenied
    case script(String)

    public var errorDescription: String? {
        switch self {
        case .automationDenied:
            "Hark is not allowed to control Google Chrome. Turn on Google Chrome under Hark in "
                + "System Settings, Privacy & Security, Automation."
        case .script(let message): "Google Chrome did not answer: \(message)"
        }
    }
}

public actor ChromeTabsSource: ItemSource {
    public nonisolated let kinds: Set<ItemKind> = [.tab]

    /// Why the last `refresh()` left the snapshot empty, when the cause was not "Chrome is quit".
    public private(set) var refreshFailure: ChromeTabsError?

    private var snapshot: [Item] = []
    private var seenActive: [String: Date] = [:]
    private var activeLastTime: Set<String> = []

    public init() {}

    public func refresh() async {
        do {
            snapshot = try await load()
            refreshFailure = nil
        } catch {
            snapshot = []
            refreshFailure = error as? ChromeTabsError ?? .script(error.localizedDescription)
        }
    }

    public func items(for command: Command) async -> [Item] {
        snapshot
    }

    /// The site (its host name, nothing more) of the front tab of the front window, or nil when Chrome
    /// is not running, is not answering, or the window is private.
    public func frontSite() async -> String? {
        guard ChromeScript.isRunning, let tabs = try? await ChromeScript.list() else { return nil }
        guard let tab = tabs.first(where: { $0.isActive && $0.inFrontWindow }), !tab.isPrivate,
              let host = URL(string: tab.url)?.host()?.lowercased(), !host.isEmpty
        else { return nil }
        return host
    }

    public func perform(_ verb: Verb, on item: Item) async throws -> UndoStep? {
        switch verb {
        case .open: try await open(item)
        case .close: try await close(item)
        case .closeDuplicates: try await closeDuplicates().undo
        default: throw SourceError.unsupported(verb, item.kind)
        }
    }

    /// Tabs that `closeDuplicates` would close, read from Chrome now.
    public func duplicates(inWindow window: String? = nil) async throws -> [Item] {
        let tabs = try await load().filter { window == nil || $0.payload["window"] == window }
        let ranked = tabs.enumerated().sorted { first, second in
            let firstUsed = first.element.lastUsed ?? .distantPast
            let secondUsed = second.element.lastUsed ?? .distantPast
            return firstUsed == secondUsed ? first.offset < second.offset : firstUsed > secondUsed
        }
        var kept: Set<String> = []
        return ranked.compactMap { entry in
            let address = Self.address(entry.element.payload["url"] ?? "")
            return kept.insert(address).inserted ? nil : entry.element
        }
    }

    /// Keeps the most recently active tab of each address and closes the rest.
    public func closeDuplicates(inWindow window: String? = nil) async throws -> (closed: Int, undo: UndoStep?) {
        let extras = try await duplicates(inWindow: window).compactMap(Self.tabID)
        guard !extras.isEmpty else { return (0, nil) }
        let closed = try await ChromeScript.close(extras)
        guard !closed.isEmpty else { return (0, nil) }
        let noun = closed.count == 1 ? "duplicate tab" : "duplicate tabs"
        let undo = UndoStep(summary: "Reopened \(closed.count) \(noun)") { try await Self.reopen(closed) }
        return (closed.count, undo)
    }

    private func open(_ item: Item) async throws -> UndoStep? {
        guard let window = Self.windowID(item), let tab = Self.tabID(item) else {
            throw SourceError.gone(item.title)
        }
        let previousApp = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleURL }
        guard let previous = try await ChromeScript.focus(window: window, tab: tab, bringForward: true) else {
            throw SourceError.gone(item.title)
        }
        return UndoStep(summary: "Went back from \(item.title)") {
            _ = try await ChromeScript.focus(window: window, tab: previous.tab, bringForward: false)
            if previous.frontWindow != window {
                try await ChromeScript.raise(window: previous.frontWindow)
            }
            guard let previousApp, Bundle(url: previousApp)?.bundleIdentifier != ChromeScript.bundleID else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: previousApp, configuration: configuration)
        }
    }

    private func close(_ item: Item) async throws -> UndoStep? {
        guard let tab = Self.tabID(item) else { throw SourceError.gone(item.title) }
        let closed = try await ChromeScript.close([tab])
        guard !closed.isEmpty else { throw SourceError.gone(item.title) }
        return UndoStep(summary: "Reopened \(item.title)") { try await Self.reopen(closed) }
    }

    private func load() async throws -> [Item] {
        guard ChromeScript.isRunning else {
            seenActive = [:]
            activeLastTime = []
            return []
        }
        let tabs = try await ChromeScript.list()
        let now = Date()
        var stamps: [String: Date] = [:]
        for tab in tabs {
            // A tab that stayed active in a background window keeps the time it was first seen
            // active, so the front window's tab stays the most recent one.
            let stillActiveBehind = tab.isActive && !tab.inFrontWindow && activeLastTime.contains(tab.id)
            stamps[tab.id] = tab.isActive && !stillActiveBehind ? now : seenActive[tab.id]
        }
        seenActive = stamps
        activeLastTime = Set(tabs.filter(\.isActive).map(\.id))
        return tabs.map { tab in
            Item(
                id: "tab:\(tab.window):\(tab.id)",
                kind: .tab,
                title: tab.title.isEmpty ? tab.url : tab.title,
                detail: Self.site(tab.url),
                owner: "Google Chrome",
                lastUsed: stamps[tab.id],
                payload: ["window": "\(tab.window)", "tab": "\(tab.id)", "index": "\(tab.index)", "url": tab.url]
            )
        }
    }

    private static func reopen(_ closed: [ChromeScript.ClosedTab]) async throws {
        var replacements: [String: String] = [:]
        let inOrder = closed.sorted { ($0.window, $0.index) < ($1.window, $1.index) }
        for tab in inOrder {
            let window = replacements[tab.window] ?? tab.window
            let used = try await ChromeScript.open(tab, inWindow: window)
            if used != window { replacements[tab.window] = used }
        }
    }

    private static func windowID(_ item: Item) -> String? { item.payload["window"] }
    private static func tabID(_ item: Item) -> String? { item.payload["tab"] }

    private static func site(_ url: String) -> String {
        guard let host = URLComponents(string: url)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func address(_ url: String) -> String {
        let withoutFragment = url.prefix { $0 != "#" }
        return String(withoutFragment.hasSuffix("/") ? withoutFragment.dropLast() : withoutFragment)
    }
}

// NSAppleScript is only safe on the main thread, so every call to Chrome hops there.
@MainActor private enum ChromeScript {
    struct LiveTab: Sendable {
        let window: String
        let index: Int
        let id: String
        let title: String
        let url: String
        let isActive: Bool
        let inFrontWindow: Bool
        /// In a private (incognito) window. Learning never looks at these.
        let isPrivate: Bool
    }

    struct ClosedTab: Sendable {
        let window: String
        let index: Int
        let url: String
        let wasActive: Bool
    }

    nonisolated static let bundleID = "com.google.Chrome"

    nonisolated static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static var compiled: NSAppleScript?

    private enum Code {
        static let id: AEKeyword = 0x4944_2020              // 'ID  '
        static let name: AEKeyword = 0x706E_616D            // 'pnam'
        static let url: AEKeyword = 0x5552_4C20             // 'URL '
        static let activeTabIndex: AEKeyword = 0x6163_5449  // 'acTI'
        static let mode: AEKeyword = 0x6D6F_6465            // 'mode'
    }

    /// Chrome calls a private window's mode "incognito". Read as a name or as its four-letter code,
    /// and when it cannot be told the window is treated as private, so nothing is learned from it.
    private static func isPrivate(_ window: NSAppleEventDescriptor) -> Bool {
        guard let mode = window.forKeyword(Code.mode) else { return true }
        let name = (mode.stringValue ?? "").lowercased()
        let code = String(format: "%c%c%c%c",
            (mode.enumCodeValue >> 24) & 0xFF, (mode.enumCodeValue >> 16) & 0xFF,
            (mode.enumCodeValue >> 8) & 0xFF, mode.enumCodeValue & 0xFF).lowercased()
        if name.contains("incog") || code == "icog" || code == "incg" { return true }
        return !(name.contains("normal") || code == "nrml" || code == "norm")
    }

    static func list() throws -> [LiveTab] {
        let result = try call("listTabs")
        guard result.numberOfItems == 2, let windows = result.atIndex(1), let tabLists = result.atIndex(2) else {
            return []
        }
        var tabs: [LiveTab] = []
        // The two lists come from separate events; a window opened in between is skipped this time.
        let windowCount = min(windows.numberOfItems, tabLists.numberOfItems)
        for windowPosition in stride(from: 1, through: windowCount, by: 1) {
            guard let properties = windows.atIndex(windowPosition),
                  let window = properties.forKeyword(Code.id)?.stringValue,
                  let active = properties.forKeyword(Code.activeTabIndex)?.int32Value,
                  let windowTabs = tabLists.atIndex(windowPosition) else { continue }
            for index in stride(from: 1, through: windowTabs.numberOfItems, by: 1) {
                guard let tab = windowTabs.atIndex(index), let id = tab.forKeyword(Code.id)?.stringValue else {
                    continue
                }
                tabs.append(LiveTab(
                    window: window,
                    index: index,
                    id: id,
                    title: tab.forKeyword(Code.name)?.stringValue ?? "",
                    url: tab.forKeyword(Code.url)?.stringValue ?? "",
                    isActive: index == Int(active),
                    inFrontWindow: windowPosition == 1,
                    isPrivate: isPrivate(properties)
                ))
            }
        }
        return tabs
    }

    static func focus(window: String, tab: String, bringForward: Bool) throws -> (frontWindow: String, tab: String)? {
        let result = try call("focusTab", [.init(string: window), .init(string: tab), .init(boolean: bringForward)])
        guard result.numberOfItems == 2, let front = result.atIndex(1)?.stringValue,
              let previous = result.atIndex(2)?.stringValue else { return nil }
        return (front, previous)
    }

    static func raise(window: String) throws {
        _ = try call("raiseWindow", [.init(string: window)])
    }

    static func close(_ tabs: [String]) throws -> [ClosedTab] {
        let ids = NSAppleEventDescriptor.list()
        for tab in tabs { ids.insert(.init(string: tab), at: 0) }
        let result = try call("closeTabs", [ids])
        return (1...max(result.numberOfItems, 1)).compactMap { position in
            guard let entry = result.atIndex(position), entry.numberOfItems == 4,
                  let window = entry.atIndex(1)?.stringValue, let index = entry.atIndex(2),
                  let url = entry.atIndex(3)?.stringValue, let wasActive = entry.atIndex(4) else { return nil }
            return ClosedTab(window: window, index: Int(index.int32Value), url: url,
                             wasActive: wasActive.booleanValue)
        }
    }

    /// Returns the window the tab landed in, which is a new one when the old window is gone.
    static func open(_ tab: ClosedTab, inWindow window: String) throws -> String {
        try call("openTab", [.init(string: window), .init(int32: Int32(tab.index)), .init(string: tab.url),
                             .init(boolean: tab.wasActive)]).stringValue ?? window
    }

    private static func call(_ handler: String, _ parameters: [NSAppleEventDescriptor] = []) throws
        -> NSAppleEventDescriptor {
        // Running the script would launch Chrome if it had quit since the last look.
        guard isRunning else { return .list() }
        let script = try compiled ?? compile()
        compiled = script

        let arguments = NSAppleEventDescriptor.list()
        for parameter in parameters { arguments.insert(parameter, at: 0) }
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(.init(string: handler.lowercased()), forKeyword: AEKeyword(keyASSubroutineName))
        event.setParam(arguments, forKeyword: keyDirectObject)

        var failure: NSDictionary?
        let result = script.executeAppleEvent(event, error: &failure)
        if let failure { throw error(from: failure) }
        return result
    }

    private static func compile() throws -> NSAppleScript {
        guard let script = NSAppleScript(source: source) else { throw ChromeTabsError.script("no script") }
        var failure: NSDictionary?
        guard script.compileAndReturnError(&failure) else {
            throw failure.map(error(from:)) ?? ChromeTabsError.script("the script did not compile")
        }
        return script
    }

    private static func error(from failure: NSDictionary) -> ChromeTabsError {
        let number = failure[NSAppleScript.errorNumber] as? Int ?? 0
        if number == errAEEventNotPermitted { return .automationDenied }
        let message = failure[NSAppleScript.errorMessage] as? String ?? "unknown error"
        return .script("\(message) (\(number))")
    }

    private static let source = """
    on listTabs()
        with timeout of 5 seconds
            tell application id "com.google.Chrome"
                return {properties of every window, properties of every tab of every window}
            end tell
        end timeout
    end listTabs

    on placeOf(tabId, tabIds)
        repeat with place from 1 to count of tabIds
            if item place of tabIds is tabId then return place
        end repeat
        return 0
    end placeOf

    on focusTab(windowId, tabId, bringForward)
        with timeout of 5 seconds
            tell application id "com.google.Chrome"
                if not (exists window id windowId) then return {}
                set theWindow to window id windowId
                set place to my placeOf(tabId, id of every tab of theWindow)
                if place is 0 then return {}
                set previousFront to id of window 1
                set previousTab to id of active tab of theWindow
                set active tab index of theWindow to place
                if bringForward then
                    set index of theWindow to 1
                    activate
                end if
                return {previousFront, previousTab}
            end tell
        end timeout
    end focusTab

    on raiseWindow(windowId)
        with timeout of 5 seconds
            tell application id "com.google.Chrome"
                if exists window id windowId then set index of window id windowId to 1
            end tell
        end timeout
    end raiseWindow

    on closeTabs(tabIds)
        set closed to {}
        with timeout of 5 seconds
            tell application id "com.google.Chrome"
                set windowIds to id of every window
                repeat with windowRef in windowIds
                    set windowId to contents of windowRef
                    set theWindow to window id windowId
                    set ids to id of every tab of theWindow
                    set addresses to URL of every tab of theWindow
                    set activePlace to active tab index of theWindow
                    repeat with place from (count of ids) to 1 by -1
                        if tabIds contains (item place of ids) then
                            set end of closed to {windowId, place, item place of addresses, place is activePlace}
                            close tab place of theWindow
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return closed
    end closeTabs

    on openTab(windowId, place, address, makeActive)
        with timeout of 5 seconds
            tell application id "com.google.Chrome"
                if not (exists window id windowId) then
                    set theWindow to make new window
                    set URL of active tab of theWindow to address
                    return id of theWindow
                end if
                set theWindow to window id windowId
                set activePlace to active tab index of theWindow
                if place > (count of tabs of theWindow) then
                    make new tab at end of tabs of theWindow with properties {URL:address}
                else
                    make new tab at before tab place of theWindow with properties {URL:address}
                    if activePlace ≥ place then set activePlace to activePlace + 1
                end if
                if not makeActive then set active tab index of theWindow to activePlace
                return windowId
            end tell
        end timeout
    end openTab
    """
}
