import SwiftUI

struct WhisperStoryHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Make it yours").font(.largeTitle.bold())
                    Text("A few small gestures. Your own story.").font(.subheadline).foregroundStyle(.secondary)
                    tip("hand.draw", title: "Move without switching", text: "Start with one finger on the words or sticker you want to move. Keep it down, then add a second finger to resize or rotate the same item.")
                    tip("textformat", title: "Edit your words", text: "Tap existing text to change it. Tap Done to return to the canvas. The undo arrow restores your previous edit.")
                    tip("square.3.layers.3d", title: "Arrange your layers", text: "Hold a sticker to bring it forward, send it back or duplicate it. Drag to the trash well and release to remove it.")
                    tip("music.note", title: "Pick the right moment", text: "Choose a song, adjust the start and length of its available preview, then listen before tapping Apply.")
                    tip("camera", title: "Try Puppy", text: "In the camera, choose Puppy from the effects rail. Face the camera in good light and open your mouth to reveal the tongue.")
                    tip("square.and.arrow.up", title: "Share when you're ready", text: "Nothing posts until you choose Share. Closing an edited Story offers draft options. Reopen this guide with the question mark anytime.")
                    Button("Got it") { dismiss() }.buttonStyle(.borderedProminent).tint(.primary).frame(maxWidth: .infinity, minHeight: 44)
                }.padding(.horizontal, 20).padding(.vertical, 20)
            }
            .navigationTitle("Story guide").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func tip(_ symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 28, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
