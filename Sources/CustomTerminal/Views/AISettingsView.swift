import SwiftUI

struct AISettingsView: View {
    @Environment(AIStore.self) private var aiStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAPIKey = false

    var body: some View {
        @Bindable var aiStore = aiStore

        VStack(alignment: .leading, spacing: 16) {

            Text("AI Settings")
                .font(.headline)

            Toggle("Enable AI features", isOn: $aiStore.isEnabled)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenRouter API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        if showAPIKey {
                            TextField("sk-or-…", text: $aiStore.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-or-…", text: $aiStore.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(showAPIKey ? "Hide" : "Show") { showAPIKey.toggle() }
                    }
                    Text("Get your key at openrouter.ai/keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
            .disabled(!aiStore.isEnabled)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $aiStore.model) {
                        ForEach(AIStore.availableModels, id: \.id) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                }
                .padding(4)
            }
            .disabled(!aiStore.isEnabled)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcuts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ShortcutRowView(key: "⌘⇧G", label: "Generate command from description")
                    ShortcutRowView(key: "⌥Tab", label: "AI tab completion on current input")
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
