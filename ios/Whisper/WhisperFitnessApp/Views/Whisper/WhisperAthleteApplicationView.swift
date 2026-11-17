import SwiftUI

/// Application form for the Whisper Athlete special-account type. Unlike
/// the coach flow this DOES NOT grant a chip badge — approval just lights
/// up the "Athlete" role label on the user's profile and unlocks athlete
/// surfaces (PR stat sheet, scouting filter, meet countdown).
struct WhisperAthleteApplicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var athlete = WhisperAthleteService.shared

    @State private var fullName: String = ""
    @State private var email: String = AuthenticationService.shared.currentUser.email ?? ""
    @State private var sport: String = ""
    @State private var level: String = "Amateur"
    @State private var team: String = ""
    @State private var prs: String = ""
    @State private var bio: String = ""
    @State private var social: String = ""

    @State private var submitting: Bool = false
    @State private var didSubmit: Bool = false
    @State private var localError: String?

    private let levels: [String] = ["Amateur", "Collegiate", "Semi-pro", "Pro", "Masters"]

    /// Warm orange-red tuned for athlete materials — pulls hot but is
    /// distinct from the coach orange so the two account types read apart.
    static let athleteAccent: Color = Color(red: 0.92, green: 0.27, blue: 0.20)

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && !sport.trimmingCharacters(in: .whitespaces).isEmpty
            && !bio.trimmingCharacters(in: .whitespaces).isEmpty
            && !submitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hero
                        if didSubmit {
                            submittedCard
                        } else {
                            perksCard
                            formCard
                            submitButton
                            if let err = localError ?? athlete.lastError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 4)
                            }
                            disclaimer
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Become an athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Self.athleteAccent)
                Text("Athlete program")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(Self.athleteAccent)
            }
            Text("Apply for the Athlete account")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Athlete is a special account type — like Coach — surfaced on your profile next to your name. No badge, no clutter. Just a clear label and the tools that come with it.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.vertical, 8)
    }

    private var perksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you unlock")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            ForEach(perks, id: \.self) { perk in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Self.athleteAccent)
                        .font(.footnote.weight(.bold))
                        .padding(.top, 2)
                    Text(perk)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private let perks: [String] = [
        "Athlete label next to your @ on every profile, comment, and DM thread.",
        "Personal-record stat sheet pinned to the top of your profile.",
        "Meet & event countdown surfaced to followers when one is upcoming.",
        "Show up in Whisper's athlete-only scouting & recruiting filter.",
        "Verified PRs pulled directly from your Whisper workouts."
    ]

    // MARK: - Form

    private var formCard: some View {
        VStack(spacing: 0) {
            field(title: "Full name", placeholder: "Jane Doe", text: $fullName)
            divider
            field(title: "Email", placeholder: "you@example.com", text: $email, keyboard: .emailAddress)
            divider
            field(title: "Sport / discipline", placeholder: "Powerlifting, Track 400m, MMA, …", text: $sport)
            divider
            levelPicker
            divider
            field(title: "Team / affiliation (optional)", placeholder: "Iron Lab Barbell Club", text: $team)
            divider
            multilineField(title: "Personal records", placeholder: "Squat 600lb @ 198 — Mar 2025\n400m 47.8s — Jun 2024\n…", text: $prs, minHeight: 100)
            divider
            multilineField(title: "About you", placeholder: "How long you've trained, biggest wins, what you're chasing next…", text: $bio, minHeight: 100)
            divider
            field(title: "Instagram / social (optional)", placeholder: "@username", text: $social)
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private func field(title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func multilineField(title: String, placeholder: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
                        .padding(.top, 2)
                }
                TextEditor(text: text)
                    .scrollContentBackground(.hidden)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(minHeight: minHeight)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Level")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(levels, id: \.self) { l in
                        Button {
                            Haptics.tap()
                            level = l
                        } label: {
                            Text(l)
                                .font(.footnote.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    level == l ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    level == l ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)
                                )
                                .overlay {
                                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().tint(.white) }
                Text(submitting ? "Submitting…" : "Submit application")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? Self.athleteAccent : WhisperTheme.muted(colorScheme).opacity(0.4), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How review works")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Your application is forwarded to \(WhisperAthleteService.reviewEmail). Approval typically takes 1–3 business days. The Athlete label appears on your profile automatically once approved.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
    }

    private var submittedCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Self.athleteAccent.opacity(0.15)).frame(width: 80, height: 80)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(Self.athleteAccent)
            }
            Text("Application submitted")
                .font(.title3.weight(.heavy))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Saved to our database and a full copy was placed on your clipboard. If Mail didn't open, paste it into any email app and send to \(WhisperAthleteService.reviewEmail).")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 12)
            Button("Done") { dismiss() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WhisperTheme.ink(colorScheme), in: Capsule())
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        localError = nil
        let ok = await athlete.submitApplication(
            fullName: fullName,
            email: email,
            sport: sport,
            level: level,
            team: team,
            prs: prs,
            bio: bio,
            social: social
        )
        submitting = false
        if ok {
            Haptics.success()
            withAnimation(.spring(response: 0.35)) { didSubmit = true }
        } else if athlete.lastError == nil {
            localError = "Couldn't submit application. Please try again."
        }
    }
}
