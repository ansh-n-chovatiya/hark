import AppKit
import CoreServices
import HarkCore

/// What the Mac itself says about the apps installed on it: the name on disk ("Visual Studio Code"), the name the app
/// gives itself ("Code"), what it is for and what it opens. Nothing names an app: the ways people say a name, the
/// editor that opens a project and the terminals that must not be sent keys are all read from here.
struct InstalledApp: Sendable {
    let url: URL
    let bundleID: String?
    /// The name on disk, without ".app".
    let folderName: String
    /// The name the app calls itself (what macOS shows for a running app).
    let shortName: String
    let category: String?
    let opensFolders: Bool
    /// Document types only a terminal declares: shell scripts and programs.
    let runsPrograms: Bool
}

enum AppNames {
    static let installed: [InstalledApp] = scan()

    private static func scan() -> [InstalledApp] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", "\(home)/Applications"]
        var apps: [InstalledApp] = []
        for folder in folders {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: "\(folder)/\(name)")
                guard let bundle = Bundle(url: url) else { continue }
                let folderName = String(name.dropLast(4))
                let info = bundle.infoDictionary ?? [:]
                let types = (info["CFBundleDocumentTypes"] as? [[String: Any]] ?? [])
                    .flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }
                apps.append(InstalledApp(
                    url: url, bundleID: bundle.bundleIdentifier, folderName: folderName,
                    shortName: (info["CFBundleName"] as? String) ?? folderName,
                    category: info["LSApplicationCategoryType"] as? String,
                    opensFolders: types.contains("public.folder"),
                    runsPrograms: types.contains("public.unix-executable") || types.contains("com.apple.terminal.shell-script")))
            }
        }
        return apps
    }

    /// Other ways to say an app's name, as the name macOS shows for it: the name on disk when it differs from the
    /// app's own ("visual studio code" for "Code"), and the initials of a long name followed by its last word, spoken
    /// or spelt out ("vs code", "vscode", "v s code").
    static func aliases() -> [String: String] {
        var table: [String: String] = [:]
        for app in installed {
            let target = app.shortName.lowercased()
            let said = AppAction.tokens(app.folderName)
            if said != AppAction.tokens(app.shortName), !said.isEmpty { table[said.joined(separator: " ")] = target }
            if said.count >= 3, let last = said.last {
                let initials = said.dropLast().compactMap(\.first).map(String.init)
                table[(initials.joined() + " " + last)] = target
                table[(initials.joined() + last)] = target
                table[(initials.joined(separator: " ") + " " + last)] = target
            }
        }
        return table
    }

    /// The installed app a name means: by its name on disk, its own name, or an alias.
    static func url(forAppNamed name: String) -> URL? {
        let wanted = AppAction.tokens(name)
        let target = AppAction.tokens(aliases()[wanted.joined(separator: " ")] ?? name)
        return installed.first { AppAction.tokens($0.folderName) == wanted || AppAction.tokens($0.shortName) == target
            || AppAction.tokens($0.shortName) == wanted }?.url
    }

    /// The name macOS shows for a running app, for a name said some other way.
    static func canonicalName(_ name: String) -> String {
        let key = AppAction.tokens(name).joined(separator: " ")
        return aliases()[key] ?? name
    }

    /// Terminals the user added in their settings, by name or bundle id (lower case).
    nonisolated(unsafe) static var extraTerminals: Set<String> = []

    /// Whether the app is a terminal: one that declares shell scripts and programs among what it opens, or one the
    /// user listed.
    static func isTerminal(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if extraTerminals.contains(bundleID.lowercased()) { return true }
        return installed.contains { $0.bundleID == bundleID && $0.runsPrograms }
    }

    static func isTerminal(named name: String) -> Bool {
        let wanted = AppAction.tokens(name)
        guard !wanted.isEmpty else { return false }
        if extraTerminals.contains(name.lowercased()) { return true }
        return installed.contains {
            $0.runsPrograms && (AppAction.tokens($0.shortName) == wanted || AppAction.tokens($0.folderName) == wanted
                || (wanted.count >= 1 && AppAction.tokens($0.folderName).starts(with: wanted)))
        }
    }

    /// Apps that open a folder as a project and are made for developers, apart from terminals.
    static var editors: [InstalledApp] {
        installed.filter { $0.opensFolders && $0.category == "public.app-category.developer-tools" && !$0.runsPrograms }
    }

    static func isEditor(named name: String) -> Bool {
        let wanted = AppAction.tokens(name)
        return editors.contains { AppAction.tokens($0.shortName) == wanted || AppAction.tokens($0.folderName) == wanted }
    }

    /// The editor for a project folder: one that is running, else the one used most recently.
    @MainActor static func preferredEditor() -> InstalledApp? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = editors
        if let live = candidates.first(where: { running.contains($0.bundleID ?? "") }) { return live }
        return candidates.max { lastUsed($0) < lastUsed($1) }
    }

    private static func lastUsed(_ app: InstalledApp) -> Date {
        guard let item = MDItemCreateWithURL(nil, app.url as CFURL),
              let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { return .distantPast }
        return date
    }
}
