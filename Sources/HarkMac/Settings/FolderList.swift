import AppKit
import SwiftUI

/// A list of folders with one clear way to add and a quieter way to remove.
struct FolderList: View {
    let title: String
    let folders: [String]
    let emptyText: String
    let helper: String
    let onChange: ([String]) -> Void

    var body: some View {
        Section {
            if folders.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 24)
            }
            ForEach(folders, id: \.self) { folder in
                FolderRow(folder: folder) {
                    onChange(folders.filter { $0 != folder })
                }
            }
            Button("Add folder…", systemImage: "plus", action: add)
        } header: {
            Text(title)
        } footer: {
            HelperText(text: helper)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = title
        guard panel.runModal() == .OK else { return }
        let chosen = panel.urls.map { NSString(string: $0.path).abbreviatingWithTildeInPath }
        onChange(folders + chosen.filter { !folders.contains($0) })
    }
}

private struct FolderRow: View {
    let folder: String
    let onRemove: () -> Void

    private var name: String {
        URL(fileURLWithPath: folder).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(folder)
                    .font(SettingsLayout.small)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 12)
            Button(action: onRemove) {
                Label("Remove \(name)", systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove \(name) from this list")
        }
    }
}
