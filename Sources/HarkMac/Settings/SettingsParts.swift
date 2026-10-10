import SwiftUI

enum SettingsLayout {
    static let width: CGFloat = 640
    static let height: CGFloat = 620
    static let fieldWidth: CGFloat = 340
    /// 12 pt, the smallest text in the window. The smaller macOS text styles are not used.
    static let small = Font.callout
}

struct HelperText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SettingsLayout.small)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ProblemText: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .font(SettingsLayout.small)
    }
}

/// A status as an icon and words together, so it never depends on colour.
struct StatusLabel: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
