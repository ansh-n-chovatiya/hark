import SwiftUI

struct PermissionsTab: View {
    let model: SettingsModel

    var body: some View {
        Form {
            GlassSection {
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
            GlassSection {
                HStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your voice stays on this Mac")
                        HelperText(text: "Speech is turned into text here. The audio is never sent anywhere.")
                    }
                }
                .frame(minHeight: 40)
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
            IconTile(symbol: symbol, theme: SettingsSection.permissions.theme, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                HelperText(text: reason)
            }
            Spacer(minLength: 12)
            statusLabel
            if status != nil && status != .granted && status != .unknown {
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
        case .unknown: StatusLabel(text: "Open your browser to check", symbol: "questionmark.circle", tint: .secondary)
        case nil: StatusLabel(text: "Checking", symbol: "ellipsis.circle", tint: .secondary)
        }
    }

    private var name: String {
        switch permission {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .automation: "Control of your browser"
        }
    }

    private var reason: String {
        switch permission {
        case .microphone: "To hear you while you hold the key."
        case .accessibility: "To notice the key, switch windows and use menus."
        case .automation: "To find and switch your browser tabs."
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
