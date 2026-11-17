import SwiftUI

/// The structured icebreaker ANSWER sheet — answering feels like answering,
/// not posting. The answer saves PRIVATELY (it quietly tunes the For-you
/// match sort) and only shares to the hub when the toggle is flipped, in
/// which case the parent opens the composer prefilled as a Q&A post.
/// Mirrors the web answer dialog exactly.
struct WhisperIcebreakerAnswerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let prompt: String
    /// Called with the Q&A post text when "share to the hub" is ON.
    let onShare: (String) -> Void
    /// Lets the hub card refresh its "Answered" state + re-sort.
    let onSaved: () -> Void

    @State private var answer: String = ""
    @State private var shareToHub: Bool = false
    @FocusState private var focused: Bool

    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    private var trimmedAnswer: String {
        answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            WhisperEmberMascot(
                                size: 44,
                                expression: .happy,
                                palette: .cupidPink,
                                smitten: true
                            )
                            Text("Answering tunes your For-you matches — it's between you and the sort, not a post.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // The structured Q&A card — prompt on top, answer under.
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                Text("THIS HOUR'S ICEBREAKER")
                                    .font(.system(size: 9.5, weight: .black))
                                    .tracking(1.4)
                            }
                            .foregroundStyle(rose)
                            Text(prompt)
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                            Rectangle()
                                .fill(rose.opacity(0.18))
                                .frame(height: 1)
                            Text("YOUR ANSWER")
                                .font(.system(size: 9.5, weight: .black))
                                .tracking(1.4)
                                .foregroundStyle(rose.opacity(0.8))
                            ZStack(alignment: .topLeading) {
                                if answer.isEmpty {
                                    Text("Say it like you'd say it on a good first date…")
                                        .font(.system(size: 14.5))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.6))
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                                TextEditor(text: $answer)
                                    .focused($focused)
                                    .font(.system(size: 14.5))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 110)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(rose.opacity(colorScheme == .dark ? 0.12 : 0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(rose.opacity(0.30), lineWidth: 1)
                        )

                        // Private by default — the whole point.
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(rose)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(rose.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Private by default")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text("Saved on your device to sharpen who you see first. Nothing posts unless you flip the share toggle.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Toggle(isOn: $shareToHub) {
                                Text("Also share to the Dating hub")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                            }
                            .tint(rose)
                            Text("Posts your answer as a Q&A card under this prompt.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        .padding(12)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))

                        Button {
                            save()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(shareToHub ? "Save & share" : "Save answer")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(trimmedAnswer.isEmpty ? rose.opacity(0.4) : rose))
                        }
                        .buttonStyle(.plain)
                        .disabled(trimmedAnswer.isEmpty)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Answer the icebreaker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            answer = WhisperDatingAnswers.answer(for: prompt) ?? ""
            focused = true
        }
    }

    private func save() {
        let text = trimmedAnswer
        guard !text.isEmpty else { return }
        Haptics.tap()
        WhisperDatingAnswers.save(prompt: prompt, answer: text)
        onSaved()
        if shareToHub {
            onShare("\(prompt)\n\(text)")
        }
        dismiss()
    }
}
