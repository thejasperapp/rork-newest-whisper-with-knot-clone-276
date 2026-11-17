import SwiftUI

/// Shares recording content between an inline notebook and its standalone library.
struct WhisperNotebookContentContainer<Content: View>: View {
    let isInline: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isInline { content() }
        else { ScrollView { content() }.scrollIndicators(.hidden) }
    }
}
