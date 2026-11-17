import SwiftUI

/// Both recipe surfaces open the same reviewed, acknowledged library save.
/// Saving a recipe is deliberately separate from logging a meal's macros.
struct WhisperRecipeSaveButton: View {
    let payload: WhisperRecipeEmbed.Payload
    var compact: Bool = false
    @State private var showsComposer: Bool = false

    var body: some View {
        Button {
            Haptics.tap()
            showsComposer = true
        } label: {
            Label("Save recipe", systemImage: "book.closed.fill")
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Review and save to Jasper, Nutrition, Recipes")
        .sheet(isPresented: $showsComposer) {
            JasperRecipesSheet(initialDraft: payload.jasperRecipeDraft)
        }
    }
}
