import HarkCore
import SwiftUI

enum HistoryStatus {
    case done, askedFirst, askedWhich, notUnderstood, failed

    init(outcome: String) {
        self = switch outcome {
        case "done": .done
        case "confirm": .askedFirst
        case "choose": .askedWhich
        case "notUnderstood": .notUnderstood
        default: .failed
        }
    }

    var isProblem: Bool {
        self == .notUnderstood || self == .failed
    }

    var words: String {
        switch self {
        case .done: "Done"
        case .askedFirst: "Asked first"
        case .askedWhich: "Asked which one"
        case .notUnderstood: "Not understood"
        case .failed: "Could not do it"
        }
    }

    var symbol: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .askedFirst: "hand.raised.fill"
        case .askedWhich: "list.bullet.circle.fill"
        case .notUnderstood: "questionmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .done: .green
        case .askedFirst, .askedWhich: .secondary
        case .notUnderstood: .orange
        case .failed: .red
        }
    }
}

enum ReportState {
    case notReported, reporting, reported
}

struct HistoryRow: View {
    let entry: Timings
    let report: ReportState
    let onStart: () -> Void
    let onSave: (String) -> Void
    let onCancel: () -> Void

    private static let symbolWidth: CGFloat = 24
    private static let spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            details
            reportLine
                .padding(.leading, Self.symbolWidth + Self.spacing)
        }
        .padding(.vertical, 2)
    }

    private var details: some View {
        let status = HistoryStatus(outcome: entry.outcome)
        return HStack(alignment: .top, spacing: Self.spacing) {
            Image(systemName: status.symbol)
                .font(.title3)
                .foregroundStyle(status.tint)
                .frame(width: Self.symbolWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.raw.isEmpty ? "Nothing heard" : entry.raw)
                    .lineLimit(2)
                (Text(status.words).fontWeight(.medium).foregroundStyle(.primary) + Text(summary))
                    .font(SettingsLayout.small)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.1f s", entry.totalMs / 1000))
                    .monospacedDigit()
                Text(entry.at, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(SettingsLayout.small)
                    .foregroundStyle(.secondary)
            }
            .help(entry.at.formatted(date: .abbreviated, time: .shortened))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var reportLine: some View {
        switch report {
        case .notReported:
            Button("This was wrong", systemImage: "exclamationmark.bubble", action: onStart)
                .buttonStyle(.borderless)
                .font(SettingsLayout.small)
                .foregroundStyle(.secondary)
                .help("Tell Hark this command did not do what you wanted")
        case .reporting:
            ReportField(onSave: onSave, onCancel: onCancel)
        case .reported:
            Label("Reported", systemImage: "checkmark.bubble")
                .font(SettingsLayout.small)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
        }
    }

    private var summary: String {
        let said = entry.summary.flatMap { $0.isEmpty ? nil : " · " + $0 } ?? ""
        // Which model answered, so a backup doing the work is never invisible.
        return said + (entry.model.map { " · via \($0)" } ?? "")
    }
}

/// One line to say what was wanted. It may be left empty.
private struct ReportField: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var wanted = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("What did you want?")
            TextField("What did you want?", text: $wanted, prompt: Text("open the other report"))
                .labelsHidden()
                .modifier(HarkPlainField())
                .focused($isFocused)
                .onSubmit { onSave(wanted) }
            Button("Save") { onSave(wanted) }
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .onAppear { isFocused = true }
    }
}
