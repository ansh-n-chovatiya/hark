import Foundation

/// Finds where a person keeps their projects, so the Folders and Projects screens are not empty on
/// the first day. It reads folder names only: never a file's contents, and nothing outside the usual
/// places for code.
public enum ProjectFinder {
    public static let usualFolders = ["Developer", "Projects", "Code", "dev", "src", "Sites", "Workspace"]
    public static let mostProjects = 12

    public struct Found: Sendable, Equatable {
        public var folders: [String]
        public var projects: [String]
    }

    /// `home` is a parameter so tests can use a made-up one. Paths come back written with `~`.
    public static func find(in home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Found {
        let manager = FileManager.default
        var folders: [String] = []
        var projects: [(path: String, changed: Date)] = []
        for name in usualFolders {
            let root = home.appending(path: name, directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            folders.append("~/\(name)")
            // Projects sit directly in the folder, or one level further down (~/Code/work/app).
            for child in subfolders(of: root) {
                if isProject(child) {
                    projects.append((tilde(child, home: home), changed(child)))
                } else {
                    for grandchild in subfolders(of: child) where isProject(grandchild) {
                        projects.append((tilde(grandchild, home: home), changed(grandchild)))
                    }
                }
            }
        }
        let recent = projects.sorted { $0.changed > $1.changed }.prefix(mostProjects).map(\.path)
        return Found(folders: folders, projects: Array(recent))
    }

    private static func subfolders(of folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func isProject(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: ".git").path)
    }

    private static func changed(_ folder: URL) -> Date {
        let git = folder.appending(path: ".git")
        return (try? git.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func tilde(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        return path.hasPrefix(base) ? "~" + path.dropFirst(base.count) : path
    }
}
