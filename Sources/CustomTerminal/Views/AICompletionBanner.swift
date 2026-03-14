import SwiftUI

/// Overlay banner shown at the bottom of the terminal when an AI completion errors.
struct AICompletionBanner: View {
    let error: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.purple)
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.purple.opacity(0.35), lineWidth: 1)
        }
        .padding(8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
