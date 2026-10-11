import SwiftUI

/// One choice in a select: what it is called, an optional second line, and an optional SF Symbol.
struct SelectOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var subtitle: String?
    var symbol: String?
    /// Why this choice cannot be picked right now. The row is greyed out and this shows beside it.
    var unavailable: String?
    /// A short label at the right of the row, such as "Recommended".
    var tag: String?
    var tagIsHighlighted = false
    /// A small symbol at the right of the row, such as a star for the recommended choice.
    var trailingSymbol: String?
    /// Starts a new group: a line is drawn above this row.
    var separatorBefore = false
    var id: Value { value }
}

/// Choose one thing from a list. Used wherever the settings offer a choice, so every list looks
/// and works the same: a field that opens a list with a tick beside the current choice, and a
/// search box when the list is long.
struct SettingsSelect<Value: Hashable>: View {
    let label: String
    let options: [SelectOption<Value>]
    @Binding var selection: Value
    var helper: String?
    var problem: String?

    var body: some View {
        SelectField(
            label: label, options: options,
            summary: options.first { $0.value == selection }?.title ?? "\(selection)",
            helper: helper, problem: problem, closesOnChoice: true,
            isSelected: { $0 == selection },
            choose: { selection = $0 })
    }
}

/// Choose several things from a list. The list stays open while ticking. At least `minimum` stay
/// ticked, so a setting that needs a value is never left empty.
struct SettingsMultiSelect<Value: Hashable>: View {
    let label: String
    let options: [SelectOption<Value>]
    @Binding var selection: [Value]
    var minimum = 1
    var placeholder = "Choose"
    var helper: String?
    var problem: String?

    var body: some View {
        SelectField(
            label: label, options: options, summary: summary, helper: helper, problem: problem,
            closesOnChoice: false,
            isSelected: { selection.contains($0) },
            choose: { value in
                if selection.contains(value) {
                    if selection.count > minimum { selection.removeAll { $0 == value } }
                } else {
                    selection.append(value)
                }
            })
    }

    private var summary: String {
        let titles = selection.map { value in options.first { $0.value == value }?.title ?? "\(value)" }
        switch titles.count {
        case 0: return placeholder
        case 1: return titles[0]
        default: return "\(titles[0]) + \(titles.count - 1) more"
        }
    }
}

struct SelectField<Value: Hashable>: View {
    /// Lists longer than this get a search box.
    private static var searchFrom: Int { 12 }

    let label: String
    let options: [SelectOption<Value>]
    let summary: String
    let helper: String?
    let problem: String?
    let closesOnChoice: Bool
    let isSelected: (Value) -> Bool
    let choose: (Value) -> Void

    @State private var isOpen = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(label)
                Spacer(minLength: 12)
                trigger.frame(width: SettingsLayout.fieldWidth)
            }
            if let problem { ProblemText(text: problem) }
            if let helper { HelperText(text: helper) }
        }
    }

    private var trigger: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                // A single choice shows its symbol in the closed field too.
                if closesOnChoice, let symbol = options.first(where: { isSelected($0.value) })?.symbol {
                    Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(summary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(summary)")
        .accessibilityHint("Opens a list to choose from")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { list }
    }

    private var shown: [SelectOption<Value>] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }

    var list: some View {
        VStack(spacing: 0) {
            if options.count > Self.searchFrom {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                Divider()
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, option in
                        if option.separatorBefore, index > 0, query.isEmpty {
                            Divider().padding(.vertical, 4).padding(.horizontal, 6)
                        }
                        OptionRow(
                            option: option, isSelected: isSelected(option.value),
                            reservesIconColumn: options.contains { $0.symbol != nil }
                        ) {
                            choose(option.value)
                            if closesOnChoice { isOpen = false }
                        }
                    }
                    if shown.isEmpty {
                        Text("Nothing matches \u{201C}\(query)\u{201D}.")
                            .font(SettingsLayout.small)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 380)
            if !closesOnChoice {
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { isOpen = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(8)
            }
        }
        .frame(width: max(SettingsLayout.fieldWidth, 280))
        .onAppear { searchFocused = options.count > Self.searchFrom }
        .onDisappear { query = "" }
    }
}

private struct OptionRow<Value: Hashable>: View {
    let option: SelectOption<Value>
    let isSelected: Bool
    /// When any row in the list has an icon, the rest keep the same gap so the names line up.
    let reservesIconColumn: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // The tick has its own column so the names line up whether or not they are chosen.
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                if let symbol = option.symbol {
                    Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
                } else if reservesIconColumn {
                    Color.clear.frame(width: 20, height: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title).lineLimit(1)
                    if let subtitle = option.subtitle {
                        Text(subtitle).font(SettingsLayout.small).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let trailing = option.trailingSymbol, option.unavailable == nil {
                    Image(systemName: trailing).foregroundStyle(.yellow).accessibilityLabel("Recommended")
                }
                if let label = option.unavailable ?? option.tag {
                    Text(label)
                        .font(SettingsLayout.small)
                        .foregroundStyle(option.tagIsHighlighted && option.unavailable == nil ? HarkBrand.accent : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                option.tagIsHighlighted && option.unavailable == nil
                                    ? HarkBrand.accent.opacity(0.14) : Color.primary.opacity(0.08)))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(option.unavailable != nil)
        .opacity(option.unavailable == nil ? 1 : 0.55)
        .onHover { isHovered = $0 && option.unavailable == nil }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(option.unavailable ?? option.tag ?? "")
    }

    private var background: Color {
        if isSelected { return HarkBrand.accent.opacity(0.14) }
        return isHovered ? Color.primary.opacity(0.08) : .clear
    }
}
