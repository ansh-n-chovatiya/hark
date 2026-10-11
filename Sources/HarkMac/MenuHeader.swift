import Observation
import SwiftUI

/// What the top of the menu says. The menu bar sets it; the view reads it.
@MainActor @Observable final class MenuHeaderState {
    var status = "Getting ready"
    /// A quieter second line: the other keys.
    var detail: String?
    /// Set when the status line can be clicked, for example to open the settings pane it names.
    var action: (() -> Void)?
    var lastCommand: String?
}

/// The card at the top of the menu: how to use Hark or what it is waiting for, and the last
/// command. A menu's own grey "disabled" lines are hard to read over its translucent background,
/// so this draws its text in the normal colours.
struct MenuHeaderView: View {
    static let width: CGFloat = 320

    let state: MenuHeaderState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let action = state.action {
                Button(action: action) { statusRow(needsAttention: true) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the setting Hark is waiting for")
            } else {
                statusRow(needsAttention: false)
            }
            if let last = state.lastCommand {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Last command").font(.callout).foregroundStyle(.secondary)
                        Text(last).font(.body).foregroundStyle(.primary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: Self.width, alignment: .leading)
    }

    private func statusRow(needsAttention: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if needsAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.16)))
                    .accessibilityHidden(true)
            } else {
                HarkMark(size: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.status)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = state.detail, !needsAttention {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if needsAttention {
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}
