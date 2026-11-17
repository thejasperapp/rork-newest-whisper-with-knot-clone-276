import SwiftUI

/// A full-height community page beside tablet navigation, never an ancestor of the retained tabs.
struct WhisperCommunityPane: View {
    @Binding var path: NavigationPath
    let onClose: () -> Void
    @State private var back: WhisperBackAction = WhisperBackAction()

    var body: some View {
        NavigationStack(path: $path) {
            WhisperCommunitiesView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { back.perform(onClose) } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 44, height: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to previous tab")
                    }.whisperFlatToolbar()
                }
                .whisperEdgeBack(isEnabled: path.isEmpty, controller: back) { back.perform(onClose) }
        }
        .background(WhisperNavigationPreview())
    }
}
