import SwiftUI

struct ShortcutRowView: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
