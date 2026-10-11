import SwiftUI

struct SettingsContent: View {
    let model: SettingsModel

    var body: some View {
        SettingsShell(model: model)
    }
}

struct SettingsTab: View {
    let section: SettingsSection
    let model: SettingsModel

    var body: some View {
        switch section {
        case .general: GeneralTab(model: model)
        case .permissions: PermissionsTab(model: model)
        case .model: UnderstandingTab(model: model)
        case .names: NamesTab(model: model)
        case .routines: RoutinesTab(model: model)
        case .learning: LearningTab(model: model)
        case .history: HistoryTab(model: model)
        }
    }
}
