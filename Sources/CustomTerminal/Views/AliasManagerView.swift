import SwiftUI

struct AliasManagerView: View {

    @Environment(AliasStore.self) private var aliasStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName    = ""
    @State private var newCommand = ""
    @State private var editingId: UUID?

    var body: some View {
        @Bindable var aliasStore = aliasStore

        VStack(spacing: 0) {

            // Header
            HStack {
                Text("Aliases")
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Dismiss")
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            // Alias list
            if aliasStore.aliases.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No aliases yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach($aliasStore.aliases) { $entry in
                        AliasRow(entry: $entry, isEditing: editingId == entry.id) {
                            editingId = editingId == entry.id ? nil : entry.id
                        }
                    }
                    .onDelete { aliasStore.delete(at: $0) }
                }
                .listStyle(.inset)
            }

            Divider()

            // Add new alias
            VStack(alignment: .leading, spacing: 8) {
                Text("Add alias")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("alias (e.g. ll)", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    TextField("command (e.g. ls -la)", text: $newCommand)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        commitNew()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 380)
    }

    private func commitNew() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        let c = newCommand.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !c.isEmpty else { return }
        aliasStore.add(name: n, command: c)
        newName    = ""
        newCommand = ""
    }
}

// MARK: - Alias Row

private struct AliasRow: View {

    @Binding var entry: AliasEntry
    let isEditing: Bool
    let onToggleEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("alias", text: $entry.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                TextField("command", text: $entry.command)
                    .textFieldStyle(.roundedBorder)
                Button("Done", action: onToggleEdit)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(entry.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(width: 110, alignment: .leading)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 10))
                Text(entry.command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(action: onToggleEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Edit \(entry.name)")
            }
        }
        .padding(.vertical, 2)
    }
}
