import SwiftUI

/// Settings screen — manage muted words. Local-only preference: any post,
/// comment, story caption, or DM body that contains one of these words is
/// hidden behind a "Muted word" veil in the UI.
struct WhisperMutedWordsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var blocks = WhisperBlockService.shared
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    helper
                    inputField
                    if !blocks.mutedWords.isEmpty {
                        list
                    } else {
                        empty
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Muted words")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var helper: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Posts, stories, comments and DMs containing these words will be hidden behind a tap-to-reveal veil.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    private var inputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Add a word or phrase", text: $draft)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .focused($fieldFocused)
                .submitLabel(.done)
                .onSubmit { commit() }
            if !draft.isEmpty {
                Button {
                    Haptics.tap()
                    commit()
                } label: {
                    Text("Add")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(blocks.mutedWords, id: \.self) { word in
                HStack {
                    Text(word)
                        .font(.body)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Spacer()
                    Button {
                        Haptics.tap()
                        blocks.removeMutedWord(word)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(8)
                            .background(WhisperTheme.surface(colorScheme), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                if word != blocks.mutedWords.last {
                    Rectangle()
                        .fill(WhisperTheme.hairline(colorScheme))
                        .frame(height: 0.5)
                        .padding(.leading, 14)
                }
            }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "text.badge.minus", height: 120)
            Text("Nothing muted yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func commit() {
        let cleaned = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        blocks.addMutedWord(cleaned)
        draft = ""
        Haptics.success()
    }
}
