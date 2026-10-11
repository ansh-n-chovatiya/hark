import SwiftUI

/// The look of the settings window: each section has its own pair of colours, used for its icon tile, its header and
/// the soft glow behind it, so a person can tell where they are at a glance. Colour is never the only signal: every
/// tile carries an SF Symbol and every state carries words.
struct SectionTheme {
    let top: Color
    let bottom: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Hark's one brand colour: the deep blue of the original app icon. It is the accent everywhere in the app (selection,
/// toggles, buttons, headers), so the icon, the menu bar menu, the overlay and Settings read as one product. Green,
/// orange and red are kept for status and always come with an icon and words.
enum HarkBrand {
    static let light = Color(red: 0.20, green: 0.38, blue: 0.95)
    static let deep = Color(red: 0.09, green: 0.14, blue: 0.42)
    /// For text, symbols and selection: readable on both light and dark windows.
    static let accent = Color(red: 0.31, green: 0.50, blue: 1.0)
    static let theme = SectionTheme(top: light, bottom: deep)
}

extension SettingsSection {
    /// Every section wears the same colours; only its symbol and title differ.
    var theme: SectionTheme { HarkBrand.theme }

    /// One plain line under the title.
    var subtitle: String {
        switch self {
        case .general: "Your keys, start-up and folders"
        case .permissions: "What macOS lets Hark do"
        case .model: "How Hark works out what you mean"
        case .names: "Your own words for things"
        case .routines: "Chores you run by name"
        case .learning: "Hark gets better as you use it"
        case .history: "What you said, and what happened"
        }
    }
}

/// A rounded tile with a gradient and a white symbol, like an app icon in System Settings.
struct IconTile: View {
    let symbol: String
    let theme: SectionTheme
    var size: CGFloat = 30
    var glow = false
    /// A calm glass tile for what is not chosen: no colour until it is.
    var quiet = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(quiet ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(theme.gradient))
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(quiet ? 0.14 : 0.28), lineWidth: 0.75)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(quiet ? AnyShapeStyle(.primary.opacity(0.85)) : AnyShapeStyle(.white))
                    .shadow(color: .black.opacity(quiet ? 0 : 0.18), radius: 1, y: 1)
            }
            .shadow(color: glow ? theme.top.opacity(0.55) : .clear, radius: glow ? size * 0.35 : 0, y: glow ? size * 0.12 : 0)
            .accessibilityHidden(true)
    }
}

/// The soft colour behind a section. It does not move, so there is nothing to turn off for Reduce Motion.
struct Backdrop: View {
    let theme: SectionTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 0.42 : 0.20
        ZStack {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.62, 0.38], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    theme.top.opacity(strength), theme.bottom.opacity(strength * 0.7), .clear,
                    theme.bottom.opacity(strength * 0.35), theme.top.opacity(strength * 0.25), .clear,
                    .clear, .clear, theme.bottom.opacity(strength * 0.18),
                ])
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The section's name, set large, with the tile it is known by and one line saying what it is for.
struct HeroHeader: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 16) {
            IconTile(symbol: section.symbol, theme: section.theme, size: 54, glow: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(section.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a row of a form sits on: frosted glass with a hairline edge.
struct RowGlass: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5) }
    }
}

/// A form section whose rows are glass, so the colour behind the window shows through the cards.
struct GlassSection<Content: View, Header: View, Footer: View>: View {
    let content: Content
    let header: Header
    let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        Section {
            content.listRowBackground(RowGlass())
        } header: {
            header
        } footer: {
            footer
        }
    }
}

extension GlassSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension GlassSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension GlassSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}
