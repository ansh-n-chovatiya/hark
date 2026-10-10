public enum SettingsSection: String, CaseIterable, Sendable {
    case general, permissions, model, names, routines, history
}

extension SettingsSection {
    var title: String {
        switch self {
        case .general: "General"
        case .permissions: "Permissions"
        case .model: "Understanding"
        case .names: "Names"
        case .routines: "Routines"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .permissions: "lock.shield"
        case .model: "sparkles"
        case .names: "character.bubble"
        case .routines: "checklist"
        case .history: "clock.arrow.circlepath"
        }
    }
}
