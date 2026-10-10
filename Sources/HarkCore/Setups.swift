import Foundation

/// A saved setup is a routine written for the user: one step per app and project folder that
/// was open when they said "save this setup as ...". Saying its name opens them all again.
public enum Setups {
    private static let editors: Set<String> = ["code", "visual studio code"]

    /// - Parameters:
    ///   - apps: names of the running apps.
    ///   - editorWindows: titles of the code editor's windows, such as "main.swift — shop-backend".
    ///   - folders: names of the folders Hark can open by name.
    public static func routine(named name: String, apps: [String], editorWindows: [String], folders: [String]) -> Routine {
        let projects = openProjects(in: editorWindows, among: folders)
        // Opening a project opens the editor too, and by its folder, which a bare "open the
        // editor" could not promise.
        let others = apps.filter { projects.isEmpty || !editors.contains($0.lowercased()) }
        let steps = projects.map { Step(say: "open the \($0) folder in VS Code") }
            + others.map { Step(say: "open \($0) app") }
        return Routine(name: name, steps: steps)
    }

    /// "3 apps and 2 projects", for telling the user what was saved.
    public static func summary(of routine: Routine) -> String {
        let projects = routine.steps.filter { $0.say?.hasSuffix("folder in VS Code") == true }.count
        let apps = routine.steps.count - projects
        let parts = [count(apps, "app"), count(projects, "project")].compactMap { $0 }
        return parts.isEmpty ? "nothing open" : parts.joined(separator: " and ")
    }

    private static func count(_ number: Int, _ word: String) -> String? {
        number == 0 ? nil : "\(number) \(word)\(number == 1 ? "" : "s")"
    }

    /// An editor window's title ends with its folder's name, after the file's.
    private static func openProjects(in titles: [String], among folders: [String]) -> [String] {
        var found: [String] = []
        for title in titles {
            guard let last = title.components(separatedBy: " — ").last?.trimmingCharacters(in: .whitespaces),
                  let folder = folders.first(where: { $0.caseInsensitiveCompare(last) == .orderedSame }),
                  !found.contains(folder)
            else { continue }
            found.append(folder)
        }
        return found
    }
}
