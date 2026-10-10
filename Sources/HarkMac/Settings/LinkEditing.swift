import Foundation

/// Web pages by name. Each row reuses `NameRow`: `said` is the name and `meant` is the address.
extension SettingsModel {
    private static let addressExample = "like https://tracker.example.com/board"

    @discardableResult func addLink() -> NameRow.ID {
        let row = NameRow(said: "", meant: "")
        links.append(row)
        return row.id
    }

    func removeLink(_ id: NameRow.ID) {
        links.removeAll { $0.id == id }
        saveLinks()
    }

    func finishEditingLink(_ id: NameRow.ID) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        links[index].wasEdited = true
        finishLinkAddress(id)
        saveLinks()
    }

    /// An address pasted without its start, like tracker.example.com/board, gets https:// put
    /// in front of it.
    func finishLinkAddress(_ id: NameRow.ID) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        let address = links[index].meant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !address.contains("://") else { return }
        links[index].meant = "https://" + address
    }

    func saveLinks() {
        var saved: [String: String] = [:]
        for index in links.indices {
            let name = links[index].said.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = links[index].meant.trimmingCharacters(in: .whitespacesAndNewlines)
            let problem = Self.problem(name: name, address: address, taken: saved)
            links[index].problem = links[index].wasEdited ? problem : nil
            if problem == nil {
                saved[name] = address
            }
        }
        update { $0.links = saved }
    }

    private static func problem(name: String, address: String, taken: [String: String]) -> String? {
        if name.isEmpty && address.isEmpty {
            return "Fill in both boxes, or remove this row."
        }
        if name.isEmpty {
            return "Type the name you will say in the first box."
        }
        if taken.keys.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return "You already have a page called \u{201C}\(name)\u{201D}. Change or remove this one."
        }
        if let problem = problem(withAddress: address, example: addressExample) {
            return problem
        }
        // Hark opens the page with `URL(string:)`, which is stricter about odd characters.
        guard URL(string: address) != nil else {
            return "This address has a character that cannot be in an address, \(addressExample)."
        }
        return nil
    }
}
