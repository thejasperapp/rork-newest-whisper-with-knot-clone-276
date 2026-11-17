import SwiftUI

/// Keeps an admitted shelf's footprint when its live content expires or is removed.
/// Only geometry is retained, never revoked content.
struct WhisperStableShelf<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        content()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > measuredHeight + 0.5 { measuredHeight = height }
            }
            .frame(minHeight: measuredHeight, alignment: .top)
            .onChange(of: dynamicTypeSize) { _, _ in measuredHeight = 0 }
    }
}
