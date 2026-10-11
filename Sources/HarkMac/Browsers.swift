import AppKit
import HarkCore

/// A web browser found on this Mac. Nothing here names a browser: an app is one when it opens web addresses and
/// publishes tabs in its scripting dictionary, and one that numbers a window's active tab is driven the way Chrome is
/// (Chrome, Brave, Edge, Arc and the other Chromium-based browsers all do).
struct BrowserApp: Sendable, Hashable {
    let bundleID: String
    let name: String
    let url: URL
}

enum Browsers {
    private struct Found { var app: BrowserApp; var hasTabs: Bool; var numbersActiveTab: Bool }

    private static let found: [Found] = {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  let sdef = scriptingDefinition(of: bundle)
            else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return Found(
                app: BrowserApp(bundleID: id, name: name, url: url),
                hasTabs: sdef.contains("class name=\"tab\""),
                numbersActiveTab: sdef.contains("active tab index"))
        }
    }()

    /// Browsers Hark can read and switch tabs in.
    static let scriptable: [BrowserApp] = found.filter(\.numbersActiveTab).map(\.app)
    /// Anything that opens web addresses and has tabs, however it is driven.
    static let all: [BrowserApp] = found.filter(\.hasTabs).map(\.app)

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return all.contains { $0.bundleID == bundleID }
    }

    /// The browser the user has chosen in System Settings.
    static var defaultBrowser: BrowserApp? {
        guard let probe = URL(string: "https://example.com"),
              let url = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let id = Bundle(url: url)?.bundleIdentifier
        else { return nil }
        return all.first { $0.bundleID == id }
    }

    /// The words that can name a browser: "browser", and each word of each browser's name.
    static var nameWords: Set<String> {
        var words: Set<String> = ["browser"]
        for app in all { words.formUnion(AppAction.tokens(app.name)) }
        return words.subtracting(["google", "app"])
    }

    /// The browser a phrase names ("brave", "google chrome"), if any.
    static func named(_ phrase: String) -> BrowserApp? {
        let words = Set(AppAction.tokens(phrase))
        return all.first { app in
            let tokens = AppAction.tokens(app.name).filter { $0 != "google" && $0 != "app" }
            return !tokens.isEmpty && tokens.allSatisfy(words.contains)
        }
    }

    private static func scriptingDefinition(of bundle: Bundle) -> String? {
        guard let name = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String else { return nil }
        let base = (name as NSString).deletingPathExtension
        guard let path = bundle.path(forResource: base, ofType: "sdef") else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}
