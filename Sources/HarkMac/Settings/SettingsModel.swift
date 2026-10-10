import Foundation
import HarkCore
import Observation

enum AddressField: Sendable {
    case online, onThisMac
}

enum KeyField: Sendable {
    case hold, typing
}

/// An address the user typed that cannot be used. It is kept so the field still shows it, with
/// the reason, after switching tabs, while the config keeps the last good address.
struct RejectedAddress: Equatable {
    var text: String
    var problem: String
}

/// What tells one command in the history from another: when it was said, to the second, and
/// what was heard. Both logs keep times as whole seconds.
struct ReportKey: Hashable {
    let second: Int
    let heard: String

    init(_ entry: Timings) {
        second = Int(entry.at.timeIntervalSince1970)
        heard = entry.raw
    }

    init(_ entry: WrongLog.Entry) {
        second = Int(entry.at.timeIntervalSince1970)
        heard = entry.heard
    }
}

struct NameRow: Identifiable, Equatable {
    let id = UUID()
    var said: String
    var meant: String
    var problem: String?
    /// Problems show only once the user has left the row, not while they are still typing in it.
    var wasEdited = false
}

@MainActor @Observable final class SettingsModel {
    nonisolated static let historyLimit = 300

    var section: SettingsSection = .general
    private(set) var config: Config
    var names: [NameRow]
    var links: [NameRow]
    var routines: [RoutineDraft]
    var selectedRoutine: RoutineDraft.ID?
    var removedRoutine: RemovedRoutine?
    private(set) var rejectedAddresses: [AddressField: RejectedAddress] = [:]
    /// A key the user chose that the other picker already uses. The picker keeps showing it, with
    /// the reason, while the config keeps the last good key.
    private(set) var rejectedKeys: [KeyField: String] = [:]
    var history: [Timings] = []
    var reportingRow: ReportKey?
    private(set) var reported: Set<ReportKey> = []
    var permissionStatuses: [Permission: PermissionStatus] = [:]
    private(set) var loginItemIsOn = false
    private(set) var loginItemProblem: String?

    let system: SettingsSystem
    private let onChange: @MainActor (Config) -> Void

    init(config: Config, system: SettingsSystem, onChange: @escaping @MainActor (Config) -> Void) {
        self.config = config
        self.system = system
        self.onChange = onChange
        names = Self.rows(for: config.aliases)
        links = Self.rows(for: config.links)
        routines = config.routines.map(RoutineDraft.init)
        selectedRoutine = routines.first?.id
    }

    /// Shows a newer config, such as the settings file after it was changed by hand, without
    /// saving anything. What the user typed that is not saved yet stays where it is.
    func reload(_ newer: Config) {
        let unsavedNames = Self.unsaved(names, in: config.aliases)
        let unsavedLinks = Self.unsaved(links, in: config.links)
        config = newer
        names = Self.rows(for: newer.aliases) + unsavedNames
        links = Self.rows(for: newer.links) + unsavedLinks
        showRoutines(from: newer.routines)
    }

    private static func unsaved(_ rows: [NameRow], in saved: [String: String]) -> [NameRow] {
        rows.filter { row in
            let said = row.said.trimmingCharacters(in: .whitespacesAndNewlines)
            return saved[said] != row.meant.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func rows(for aliases: [String: String]) -> [NameRow] {
        aliases
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { NameRow(said: $0.key, meant: $0.value) }
    }

    func update(_ change: (inout Config) -> Void) {
        var changed = config
        change(&changed)
        guard changed != config else { return }
        config = changed
        onChange(changed)
    }

    // MARK: Keys

    func key(_ field: KeyField) -> String {
        rejectedKeys[field] ?? savedKey(field)
    }

    func keyProblem(_ field: KeyField) -> String? {
        guard rejectedKeys[field] != nil else { return nil }
        switch field {
        case .hold: return "Choose a different key from the one you tap for typing."
        case .typing: return "Choose a different key from the one you hold to speak."
        }
    }

    func setKey(_ key: String, for field: KeyField) {
        let other: KeyField = field == .hold ? .typing : .hold
        guard key.isEmpty || key != savedKey(other) else {
            rejectedKeys[field] = key
            return
        }
        rejectedKeys[field] = nil
        save(key, for: field)
        if let waiting = rejectedKeys[other], waiting != key {
            rejectedKeys[other] = nil
            save(waiting, for: other)
        }
    }

    private func savedKey(_ field: KeyField) -> String {
        field == .hold ? config.hotkey : config.typeKey
    }

    private func save(_ key: String, for field: KeyField) {
        update { config in
            switch field {
            case .hold: config.hotkey = key
            case .typing: config.typeKey = key
            }
        }
    }

    // MARK: Addresses

    func address(_ field: AddressField) -> String {
        if let rejected = rejectedAddresses[field] { return rejected.text }
        return field == .online ? config.modelURL : config.fallbackModelURL
    }

    func setAddress(_ text: String, for field: AddressField) {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = Self.problem(withAddress: address) {
            rejectedAddresses[field] = RejectedAddress(text: text, problem: problem)
            return
        }
        rejectedAddresses[field] = nil
        update { config in
            switch field {
            case .online: config.modelURL = address
            case .onThisMac: config.fallbackModelURL = address
            }
        }
    }

    static func problem(withAddress address: String, example: String = "like http://127.0.0.1:11434/v1") -> String? {
        guard !address.isEmpty else {
            return "Type an address that starts with http:// or https://, \(example)."
        }
        guard let parts = URLComponents(string: address), let scheme = parts.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return "This address must start with http:// or https://, \(example)."
        }
        guard parts.host?.isEmpty == false else {
            return "This address is missing the part after http://, \(example)."
        }
        return nil
    }

    // MARK: Names

    @discardableResult func addName() -> NameRow.ID {
        let row = NameRow(said: "", meant: "")
        names.append(row)
        return row.id
    }

    func removeName(_ id: NameRow.ID) {
        names.removeAll { $0.id == id }
        saveNames()
    }

    func finishEditingName(_ id: NameRow.ID) {
        guard let index = names.firstIndex(where: { $0.id == id }) else { return }
        names[index].wasEdited = true
        saveNames()
    }

    func saveNames() {
        var aliases: [String: String] = [:]
        for index in names.indices {
            let said = names[index].said.trimmingCharacters(in: .whitespacesAndNewlines)
            let meant = names[index].meant.trimmingCharacters(in: .whitespacesAndNewlines)
            let problem = Self.problem(said: said, meant: meant, taken: aliases)
            names[index].problem = names[index].wasEdited ? problem : nil
            if problem == nil {
                aliases[said] = meant
            }
        }
        update { $0.aliases = aliases }
    }

    private static func problem(said: String, meant: String, taken: [String: String]) -> String? {
        if said.isEmpty && meant.isEmpty {
            return "Fill in both boxes, or remove this row."
        }
        if said.isEmpty {
            return "Type the words you will say in the first box."
        }
        if meant.isEmpty {
            return "Type what Hark should understand in the second box."
        }
        if taken.keys.contains(where: { $0.caseInsensitiveCompare(said) == .orderedSame }) {
            return "You already have a name for \u{201C}\(said)\u{201D}. Change or remove this one."
        }
        return nil
    }

    // MARK: Login item

    func refreshLoginItem() {
        loginItemIsOn = system.loginItemIsOn()
    }

    func setLoginItem(_ on: Bool) {
        do {
            try system.setLoginItem(on)
            loginItemProblem = nil
        } catch {
            loginItemProblem = "Hark could not change this: \(error.localizedDescription)"
        }
        refreshLoginItem()
    }

    // MARK: Permissions and history

    /// Asking macOS about Chrome can take a moment, so the answers are gathered off the main thread.
    func refreshPermissions() async {
        let status = system.permissionStatus
        permissionStatuses = await Task.detached {
            Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, status($0)) })
        }.value
    }

    func refreshHistory() async {
        let read = system.history
        let readReports = system.reports
        let (history, reports) = await Task.detached {
            (Array(read().suffix(Self.historyLimit).reversed()), readReports())
        }.value
        self.history = history
        showReports(reports)
    }

    /// Adds to the marks instead of replacing them, so a row reported in this session keeps its
    /// mark even if the file could not be written.
    func showReports(_ entries: [WrongLog.Entry]) {
        reported.formUnion(entries.map(ReportKey.init))
    }

    func isReported(_ entry: Timings) -> Bool {
        reported.contains(ReportKey(entry))
    }

    func report(_ entry: Timings, wanted: String) {
        let did = entry.summary.flatMap { $0.isEmpty ? nil : $0 } ?? HistoryStatus(outcome: entry.outcome).words
        let report = WrongLog.Entry(
            at: entry.at, heard: entry.raw, did: did, wanted: wanted.trimmingCharacters(in: .whitespacesAndNewlines))
        system.report(report)
        reported.insert(ReportKey(entry))
        reportingRow = nil
    }
}
