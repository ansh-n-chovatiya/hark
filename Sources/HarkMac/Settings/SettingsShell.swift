import SwiftUI

/// The settings window: a glass sidebar on the left, and on the right the section's header over its content.
struct SettingsShell: View {
    let model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let section = model.section
        HStack(spacing: 0) {
            Sidebar(model: model, choose: choose)
                .frame(width: SettingsLayout.sidebar)
            VStack(spacing: 0) {
                HeroHeader(section: section)
                    .padding(.horizontal, 30)
                    .padding(.top, 34)
                    .padding(.bottom, 6)
                SettingsTab(section: section, model: model)
                    .scrollContentBackground(.hidden)
                    .id(section)
            }
            .frame(maxWidth: .infinity)
        }
        .background { Backdrop(theme: HarkBrand.theme) }
        .tint(HarkBrand.accent)
        .frame(width: SettingsLayout.width, height: SettingsLayout.height)
        .task { await model.refreshPermissions() }
    }

    private func choose(_ section: SettingsSection) {
        if reduceMotion {
            model.section = section
        } else {
            withAnimation(.snappy(duration: 0.28)) { model.section = section }
        }
    }
}

private struct Sidebar: View {
    let model: SettingsModel
    let choose: (SettingsSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            brand
                .padding(.bottom, 14)
            ForEach(SettingsSection.allCases, id: \.self) { section in
                SidebarRow(section: section, selected: model.section == section) { choose(section) }
            }
            Spacer(minLength: 0)
            status
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) { Rectangle().fill(.primary.opacity(0.08)).frame(width: 0.5) }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(HarkBrand.theme.gradient)
                    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 0.75) }
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: HarkBrand.light.opacity(0.5), radius: 9, y: 3)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hark").font(.system(size: 19, weight: .bold, design: .rounded))
                Text("Version \(Self.version)").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    /// Whether Hark can do its job, in words and a symbol; choosing it goes to Permissions when something is missing.
    private var status: some View {
        let missing = model.permissionStatuses.values.contains { $0 == .denied || $0 == .notAsked }
        return Button {
            if missing { choose(.permissions) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: missing ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(missing ? .orange : .green)
                Text(missing ? "Needs a permission" : "Ready to listen")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(missing ? "Opens Permissions" : "")
    }

    private static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                IconTile(symbol: section.symbol, theme: section.theme, size: 28, glow: selected, quiet: !selected)
                Text(section.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.78))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular.tint(section.theme.top.opacity(0.22)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
