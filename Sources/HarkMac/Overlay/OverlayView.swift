import AppKit
import HarkCore
import SwiftUI

enum OverlayStyle {
    static let lead = Font.system(size: 15, weight: .medium)
    static let row = Font.system(size: 14, weight: .medium)
    static let small = Font.system(size: 12)
    static let icon = Font.system(size: 16, weight: .medium)
}

struct OverlayView: View {
    let model: OverlayModel

    private static let cardWidth: CGFloat = 440
    private static let cornerRadius: CGFloat = 16

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    @ViewBuilder private var card: some View {
        if case .hidden = model.state {
            EmptyView()
        } else {
            let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(width: Self.cardWidth, alignment: .leading)
                .background(HUDMaterial().clipShape(shape))
                .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
                .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .listening:
            StatusLine(text: "Listening", textStyle: .secondary) { ListeningMark() }
        case .hearing(let text):
            StatusLine(text: text.isEmpty ? "Listening" : text, textStyle: text.isEmpty ? .secondary : .primary) {
                ListeningMark()
            }
            .truncationMode(.head)
        case .working(let heard):
            VStack(alignment: .leading, spacing: 4) {
                StatusLine(text: heard.isEmpty ? "One moment" : heard, textStyle: heard.isEmpty ? .secondary : .primary) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                }
                // Says the wait is Hark thinking, not Hark stuck.
                Text("Working on it")
                    .font(OverlayStyle.small)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
        case .result(let text):
            StatusLine(text: text, textStyle: .primary) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .answer(let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.bubble.fill")
                    .font(OverlayStyle.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(text)
                    .font(OverlayStyle.lead)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .error(let text):
            StatusLine(text: text, textStyle: .primary) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        case .choices(let matches):
            ChoiceList(matches: Array(matches.prefix(Overlay.maxChoices)))
        case .confirm(let question):
            ConfirmPrompt(question: question)
        }
    }
}

private struct StatusLine<Icon: View>: View {
    let text: String
    let textStyle: HierarchicalShapeStyle
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(OverlayStyle.icon)
                .frame(width: 20, height: 20)
            Text(text)
                .font(OverlayStyle.lead)
                .foregroundStyle(textStyle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ListeningMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PulsingSymbol(name: "waveform", pulses: !reduceMotion)
            .accessibilityHidden(true)
    }
}

/// The pulse is a layer animation, which the system draws without Hark's main thread. A SwiftUI
/// symbol effect redraws on the main thread for every frame, and when the screen is slow to
/// answer each redraw waits for it: the key's release then queues up behind the drawing and the
/// panel sits on "Listening".
private struct PulsingSymbol: NSViewRepresentable {
    let name: String
    let pulses: Bool

    private static let pulseKey = "pulse"

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        view.contentTintColor = .controlAccentColor
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard let layer = view.layer else { return }
        guard pulses else {
            layer.removeAnimation(forKey: Self.pulseKey)
            return
        }
        guard layer.animation(forKey: Self.pulseKey) == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: Self.pulseKey)
    }
}

private struct ChoiceList: View {
    let matches: [Match]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which one?")
                .font(OverlayStyle.small.weight(.medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                    ChoiceRow(
                        number: index + 1,
                        title: match.item.title,
                        subtitle: subtitle(for: match.item),
                        symbol: symbol(for: match.item.kind)
                    )
                }
            }
            KeyHint(text: "Press a number to choose, or Esc to cancel")
        }
    }

    private func subtitle(for item: Item) -> String {
        [item.detail, item.owner].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func symbol(for kind: ItemKind) -> String {
        switch kind {
        case .app: "app"
        case .window: "macwindow"
        case .tab: "globe"
        case .file: "doc"
        case .clip: "doc.on.clipboard"
        case .workspace: "square.grid.2x2"
        case .routine: "play.circle"
        }
    }
}

private struct ConfirmPrompt: View {
    let question: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .font(OverlayStyle.lead)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                ChoiceRow(number: 1, title: "Yes", subtitle: "")
                ChoiceRow(number: 2, title: "No", subtitle: "")
            }
            KeyHint(text: "Press 1 or 2, or Esc to cancel")
        }
    }
}

private struct ChoiceRow: View {
    let number: Int
    let title: String
    let subtitle: String
    var symbol: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Keycap(label: "\(number)")
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OverlayStyle.row)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OverlayStyle.small)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .truncationMode(.middle)
            if let symbol {
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(OverlayStyle.row)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Keycap: View {
    let label: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .frame(width: 24, height: 24)
            .background(.primary.opacity(0.08), in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.25), lineWidth: 1))
    }
}

private struct KeyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OverlayStyle.small)
            .foregroundStyle(.secondary)
    }
}

struct HUDMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        // The panel never becomes key, so the default state would draw the dull inactive material.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
