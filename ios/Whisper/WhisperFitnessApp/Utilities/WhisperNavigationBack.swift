import SwiftUI

extension View {
    /// Replaces a native destination's arrow and edge action as one scope.
    func whisperNavigationBack(isEnabled: Bool = true) -> some View {
        modifier(WhisperNavigationBackModifier(enabled: isEnabled))
    }
}

private struct WhisperNavigationBackModifier: ViewModifier {
    let enabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var back: WhisperBackAction = WhisperBackAction()

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { back.perform { dismiss() } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium))
                            .frame(width: 44, height: 44).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled).accessibilityLabel("Back")
                }.whisperFlatToolbar()
            }
            .whisperEdgeBack(isEnabled: enabled, controller: back) { back.perform { dismiss() } }
    }
}
