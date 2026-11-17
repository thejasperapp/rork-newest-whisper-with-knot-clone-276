import SwiftUI

/// Explainer popup shown exactly once when the signed-in user earns the
/// "Liar Liar" badge. Surfaces the reason, the appeal CTA, and a dismiss
/// action that records `acknowledged_at` in Supabase.
struct WhisperLiarLiarPopup: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let row: WhisperLiarLiarBadgeRow
    @State private var presentAppeal: Bool = false
    @State private var dismissing: Bool = false

    private var strikeCount: Int { row.strike_count ?? WhisperLiarLiarService.strikeThreshold }

    var body: some View {
        VStack(spacing: 0) {
            // Floating clown crest with a soft red glow underneath.
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red.opacity(0.35), Color.red.opacity(0)],
                            center: .center, startRadius: 4, endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                Text("\u{1F921}")
                    .font(.system(size: 96))
                    .shadow(color: Color.red.opacity(0.45), radius: 8, y: 3)
            }
            .padding(.top, 22)

            Text("You got the Liar Liar badge")
                .font(.title2.weight(.heavy))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 6)

            Text("Jasper flagged \(strikeCount) of your recent posts as false or misleading.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 6)

            // Reason card (auto-generated, includes most recent flagged claim).
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                    Text("Why you got this")
                        .font(.caption.weight(.heavy))
                        .tracking(0.4)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Text(row.reason ?? "You received \(strikeCount) false or misleading fact-checks in the last 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            // What it means
            VStack(alignment: .leading, spacing: 10) {
                bullet("This chip appears next to your name across Whisper.")
                bullet("Jasper will keep auto-checking your claims — accurate posts won't add strikes.")
                bullet("You can appeal below if you think this was a mistake.")
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    presentAppeal = true
                } label: {
                    Text("Apply to remove")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(row.hasAppealedPending)
                .opacity(row.hasAppealedPending ? 0.5 : 1)

                if row.hasAppealedPending {
                    Text("Appeal already submitted — we're reviewing it.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }

                Button {
                    Haptics.tap()
                    Task {
                        dismissing = true
                        await WhisperLiarLiarService.shared.acknowledgePopup()
                        dismiss()
                    }
                } label: {
                    Text("I understand")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(dismissing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(WhisperTheme.surface(colorScheme))
        .sheet(isPresented: $presentAppeal) {
            WhisperLiarLiarAppealView()
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Appeal sheet — the user writes a short explanation, we insert into
/// `whisper_liar_appeals` and flip the badge into "pending review".
struct WhisperLiarLiarAppealView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var appealText: String = ""
    @State private var submitting: Bool = false
    @State private var submitted: Bool = false
    @FocusState private var focused: Bool

    private var canSubmit: Bool {
        appealText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 && !submitting
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("\u{1F921}")
                    .font(.system(size: 26))
                Text("Appeal your Liar Liar badge")
                    .font(.title3.weight(.heavy))
            }
            .padding(.top, 4)

            Text("Tell us why the flagged posts were actually accurate, and link any sources you'd like us to consider. We typically respond within 2–3 days.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if appealText.isEmpty {
                    Text("Explain why this was wrong…")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.top, 12)
                        .padding(.leading, 14)
                }
                TextEditor(text: $appealText)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
            }
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }

            if submitted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Appeal submitted — we'll be in touch.")
                        .font(.subheadline.weight(.semibold))
                }
            }

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                Task {
                    submitting = true
                    let ok = await WhisperLiarLiarService.shared.submitAppeal(body: appealText)
                    submitting = false
                    if ok {
                        submitted = true
                        try? await Task.sleep(for: .milliseconds(900))
                        dismiss()
                    }
                }
            } label: {
                Text(submitting ? "Sending…" : "Submit appeal")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        (canSubmit ? WhisperTheme.ink(colorScheme) : WhisperTheme.ink(colorScheme).opacity(0.3)),
                        in: .rect(cornerRadius: 14)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(20)
    }

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle("Appeal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .onAppear { focused = true }
    }
}
