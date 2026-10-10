import SwiftUI

struct PermissionsTab: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission, status: model.permissionStatuses[permission]) {
                        model.system.openPermissionSettings(permission)
                    }
                }
            } header: {
                Text("Hark needs these to work. You can change them any time in System Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                await model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    /// Nil until macOS has answered for the first time.
    let status: PermissionStatus?
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                HelperText(text: reason)
            }
            Spacer(minLength: 12)
            statusLabel
            if status != nil && status != .granted {
                Button("Open settings", action: openSettings)
                    .accessibilityLabel("Open settings for \(name)")
            }
        }
        .frame(minHeight: 40)
    }

    @ViewBuilder private var statusLabel: some View {
        switch status {
        case .granted: StatusLabel(text: "Allowed", symbol: "checkmark.circle.fill", tint: .green)
        case .denied, .notAsked: StatusLabel(text: "Needed", symbol: "exclamationmark.triangle.fill", tint: .orange)
        case nil: StatusLabel(text: "Checking", symbol: "ellipsis.circle", tint: .secondary)
        }
    }

    private var name: String {
        switch permission {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .automation: "Control of Google Chrome"
        }
    }

    private var reason: String {
        switch permission {
        case .microphone: "To hear you while you hold the key."
        case .accessibility: "To notice the key, switch windows and use menus."
        case .automation: "To find and switch your Chrome tabs."
        }
    }

    private var symbol: String {
        switch permission {
        case .microphone: "mic"
        case .accessibility: "accessibility"
        case .automation: "globe"
        }
    }
}
