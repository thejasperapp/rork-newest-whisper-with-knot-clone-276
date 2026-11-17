import SwiftUI

/// Inline "Readers added context" card rendered under a post when the
/// community has surfaced a high-scoring note. Mirrors the Twitter /
/// X-style community-notes card but stays minimal so it doesn't overpower
/// the original post.
struct WhisperCommunityNoteInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let note: WhisperCommunityNote
    let totalNotes: Int
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Text("Readers added context")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Spacer(minLength: 0)
                    if totalNotes > 1 {
                        Text("\(totalNotes) notes")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                HStack(spacing: 6) {
                    Text("\u{2014} @\(note.author_username)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Spacer(minLength: 0)
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.caption2)
                    Text("\(note.helpful_count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Full sheet listing every community note for a post, plus a composer to
/// add a new one. Votes are toggled with the up / down chips on each note.
struct WhisperCommunityNotesSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let postID: String

    @State private var service = WhisperCommunityNotesService.shared
    @State private var composerText: String = ""
    @State private var composerFocused: Bool = false
    @State private var posting: Bool = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private var notes: [WhisperCommunityNote] {
        service.notes(forPostID: postID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        explainer
                        composer
                        if !notes.isEmpty {
                            Text(notes.count == 1 ? "1 note" : "\(notes.count) notes")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .padding(.top, 4)
                            ForEach(notes) { n in
                                noteRow(n)
                            }
                        } else {
                            emptyState
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Community notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task { await service.refresh(postID: postID) }
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                Text("Add helpful context")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Notes are written by readers like you. The most helpful note (most up-votes) appears under the post. Cite a source where possible.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "Write a note that adds context, evidence, or a correction\u{2026}",
                text: $composerText,
                axis: .vertical
            )
            .focused($fieldFocused)
            .lineLimit(3...8)
            .padding(12)
            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
            }
            HStack {
                Text("\(composerText.count)/500")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.red)
                }
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 6) {
                        if posting { ProgressView().controlSize(.small) }
                        Text(posting ? "Posting\u{2026}" : "Post note")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .opacity(canSubmit ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "note.text", height: 120)
            Text("No notes yet")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Be the first to add context to this post.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func noteRow(_ n: WhisperCommunityNote) -> some View {
        let myVote = service.myVotes[n.id] ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text(n.body)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            HStack(spacing: 14) {
                Text("@\(n.author_username)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer(minLength: 0)
                voteChip(
                    icon: myVote == 1 ? "hand.thumbsup.fill" : "hand.thumbsup",
                    count: n.helpful_count,
                    active: myVote == 1,
                    tint: Color(red: 0.18, green: 0.78, blue: 0.32)
                ) {
                    Task { await service.vote(on: n, value: 1) }
                }
                voteChip(
                    icon: myVote == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                    count: n.not_helpful_count,
                    active: myVote == -1,
                    tint: Color.red
                ) {
                    Task { await service.vote(on: n, value: -1) }
                }
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    private func voteChip(icon: String, count: Int, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                Text("\(count)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(active ? tint : WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(WhisperTheme.surface(colorScheme))
            )
            .overlay {
                Capsule().strokeBorder(
                    active ? tint.opacity(0.6) : WhisperTheme.hairline(colorScheme),
                    lineWidth: 0.5
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var canSubmit: Bool {
        let t = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= 10 && t.count <= 500 && !posting
    }

    private func submit() async {
        guard canSubmit else { return }
        posting = true
        errorMessage = nil
        let ok = await service.addNote(postID: postID, body: composerText)
        posting = false
        if ok {
            composerText = ""
            fieldFocused = false
            Haptics.success()
        } else {
            errorMessage = "Couldn't post note. Try again."
            Haptics.warning()
        }
    }
}
