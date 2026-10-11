import SwiftUI

enum SettingsLayout {
    static let sidebar: CGFloat = 210
    static let width: CGFloat = 900
    static let height: CGFloat = 660
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
            Text(text).font(.callout.weight(.medium))
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 84, height: 84)
                .glassEffect(.regular, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A binding to one row of a list, found by its identity each time it is read, not by its position. A row that is
/// removed while something still holds its binding (a text box giving up focus as the row goes) reads as the
/// placeholder and ignores writes, where a binding by position would crash on an index that no longer exists.
enum RowBinding {
    static func make<Row: Identifiable>(_ rows: Binding<[Row]>, id: Row.ID, placeholder: Row) -> Binding<Row> {
        Binding(
            get: { rows.wrappedValue.first { $0.id == id } ?? placeholder },
            set: { newValue in
                guard let index = rows.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
                rows.wrappedValue[index] = newValue
            })
    }
}
