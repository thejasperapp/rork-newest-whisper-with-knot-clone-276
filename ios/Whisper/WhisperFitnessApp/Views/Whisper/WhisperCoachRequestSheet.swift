import SwiftUI

/// Compact sheet shown from `WhisperUserProfileView` when a viewer taps the
/// "Ask to coach me" button on a verified coach's profile. Lets them write
/// a short pitch (goals, current routine, schedule) and fires off the
/// `whisper_coach_requests` row via `WhisperCoachRequestService`.
struct WhisperCoachRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let coach: WhisperUserRow

    @State private var requests = WhisperCoachRequestService.shared
    @State private var message: String = ""
    @State private var submitting: Bool = false
    @State private var submitted: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                if submitted {
                    successState
                } else {
                    formState
                }
            }
            .navigationTitle(submitted ? "Request sent" : "Ask to coach me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private var formState: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    WhisperAvatar(
                        username: coach.username,
                        size: 64,
                        imageURL: coach.profile_image_url.flatMap { URL(string: $0) }
                    )
                    HStack(spacing: 4) {
                        Text("@\(coach.username)")
                            .font(.headline.weight(.bold))
                        WhisperCoachBadge(size: 13)
                    }
                    Text("Approved coach")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.coachAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(WhisperTheme.coachAccent.opacity(0.12), in: Capsule())
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your pitch")
                        .font(.subheadline.weight(.bold))
                    Text("Share your goals, current routine, and what you'd like help with.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("Hey! I'd love to train with you. My main goal is…")
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(WhisperTheme.coachAccent)
                        Text("If they accept, you'll share:")
                            .font(.caption.weight(.semibold))
                    }
                    permRow("Nutrition totals (calories, protein, carbs, fat, water)")
                    permRow("Sleep, steps and recent workouts")
                    permRow("Your latest progress photos (front / side / back)")
                    Text("You can revoke access any time from Settings → My coaches.")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.top, 4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
                .padding(.horizontal, 16)

                if let err = requests.lastError {
                    Text(err)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.85), in: .rect(cornerRadius: 10))
                        .padding(.horizontal, 16)
                }

                Button {
                    Haptics.tap()
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if submitting { ProgressView().tint(.white) }
                        Text(submitting ? "Sending…" : "Send request")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? WhisperTheme.coachAccent : WhisperTheme.muted(colorScheme).opacity(0.4), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || submitting)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var successState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(WhisperTheme.coachAccent.opacity(0.18))
                    .frame(width: 80, height: 80)
                Image(systemName: "paperplane.fill")
                    .font(.largeTitle)
                    .foregroundStyle(WhisperTheme.coachAccent)
            }
            Text("Request sent to @\(coach.username)")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("They'll see it in their Coach Studio. Once they accept, your nutrition, sleep and progress photos will start syncing to them automatically.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(WhisperTheme.coachAccent, in: Capsule())
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .padding(.top, 48)
    }

    private func permRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(WhisperTheme.coachAccent)
            Text(text)
                .font(.caption)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
    }

    private var canSubmit: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        let ok = await requests.requestCoach(
            coachUserID: coach.user_id,
            coachUsername: coach.username,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if ok {
            Haptics.success()
            // Kick off an immediate snapshot upload so the coach sees data
            // the moment they accept.
            Task { await WhisperClientSnapshotService.shared.uploadIfNeeded(force: true) }
            withAnimation(.spring(response: 0.35)) { submitted = true }
        }
    }
}
