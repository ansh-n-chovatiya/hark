import HarkCore
import SwiftUI

struct HistoryTab: View {
    let model: SettingsModel
    @State private var filter = HistoryFilter.all

    private var shown: [Timings] {
        switch filter {
        case .all: model.history
        case .problems: model.history.filter { HistoryStatus(outcome: $0.outcome).isProblem || model.isReported($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $filter) {
                Text("All").tag(HistoryFilter.all)
                Text("Problems").tag(HistoryFilter.problems)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 16)
            .padding(.bottom, 8)
            HelperText(text: "Mark a command that went wrong and it becomes something to fix.")
                .padding(.bottom, 4)
            content
        }
        .task { await model.refreshHistory() }
    }

    @ViewBuilder private var content: some View {
        let shown = shown
        if model.history.isEmpty {
            EmptyState(symbol: "clock", text: "Commands you speak or type will show up here.")
        } else if shown.isEmpty {
            EmptyState(symbol: "checkmark.circle", text: "No problems. Choose All to see every command.")
        } else {
            Form {
                GlassSection {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, entry in
                        HistoryRow(entry: entry, report: reportState(of: entry)) {
                            model.reportingRow = ReportKey(entry)
                        } onSave: { wanted in
                            model.report(entry, wanted: wanted)
                        } onCancel: {
                            model.reportingRow = nil
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

extension HistoryTab {
    fileprivate func reportState(of entry: Timings) -> ReportState {
        if model.isReported(entry) { return .reported }
        return model.reportingRow == ReportKey(entry) ? .reporting : .notReported
    }
}

private enum HistoryFilter {
    case all, problems
}
