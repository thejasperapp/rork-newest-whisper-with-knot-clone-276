import SwiftUI

/// Full-screen application form gating coach status. Users fill out their
/// credentials, why they want to coach, and hit Submit. The service writes
/// the row to Supabase AND opens a prefilled mailto: to the review inbox.
struct WhisperCoachApplicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var coach = WhisperCoachService.shared

    @State private var fullName: String = ""
    @State private var email: String = AuthenticationService.shared.currentUser.email ?? ""
    @State private var credentials: String = ""
    @State private var specialtiesText: String = ""
    @State private var experienceYears: Int = 1
    @State private var bio: String = ""
    @State private var website: String = ""
    @State private var social: String = ""

    @State private var submitting: Bool = false
    @State private var didSubmit: Bool = false
    @State private var localError: String?

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && !credentials.trimmingCharacters(in: .whitespaces).isEmpty
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
                            formCard
                            submitButton
                            if let err = localError ?? coach.lastError {
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
            .navigationTitle("Become a coach")
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
                WhisperCoachBadge(size: 24)
                Text("Coach program")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(WhisperTheme.coachAccent)
            }
            Text("Apply to become a Whisper coach")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Verified coaches get a badge on every Whisper screen, can build workout programs, and send them directly to clients' Whisper app.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.vertical, 8)
    }

    // MARK: - Form

    private var formCard: some View {
        VStack(spacing: 0) {
            field(title: "Full name", placeholder: "Jane Doe", text: $fullName)
            divider
            field(title: "Email", placeholder: "you@example.com", text: $email, keyboard: .emailAddress)
            divider
            stepperRow
            divider
            field(title: "Specialties", placeholder: "Strength, Hypertrophy, Mobility", text: $specialtiesText)
            divider
            multilineField(title: "Credentials / certifications", placeholder: "NASM-CPT, 5 years training collegiate athletes, …", text: $credentials, minHeight: 90)
            divider
            multilineField(title: "Why do you want to coach on Whisper?", placeholder: "Tell us about your training philosophy…", text: $bio, minHeight: 110)
            divider
            field(title: "Website (optional)", placeholder: "https://your-site.com", text: $website, keyboard: .URL)
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
                .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .URL)
                .textInputAutocapitalization(keyboard == .emailAddress || keyboard == .URL ? .never : .sentences)
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

    private var stepperRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Experience")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text("\(experienceYears) year\(experienceYears == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Spacer()
            Stepper("", value: $experienceYears, in: 0...50)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
            .background(canSubmit ? WhisperTheme.coachAccent : WhisperTheme.muted(colorScheme).opacity(0.4), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How review works")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Your application is forwarded to \(WhisperCoachService.reviewEmail). Approval typically takes 1–3 business days. You'll see your coach badge appear automatically once approved.")
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
                Circle().fill(WhisperTheme.coachAccent.opacity(0.15)).frame(width: 80, height: 80)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(WhisperTheme.coachAccent)
            }
            Text("Application submitted")
                .font(.title3.weight(.heavy))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Saved to our database and the full application was copied to your clipboard. If Mail didn't open, paste it into any email app and send to \(WhisperCoachService.reviewEmail).")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 12)
            if coach.didCopyReviewEmail {
                Label("Application copied to clipboard", systemImage: "doc.on.doc.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.coachAccent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(WhisperTheme.coachAccent.opacity(0.12), in: Capsule())
            }
            Button {
                if let body = coach.lastReviewEmailBody {
                    UIPasteboard.general.string = body
                    Haptics.success()
                }
            } label: {
                Label("Copy email again", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.card(colorScheme).opacity(0.001))
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
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
        let specialties = specialtiesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let ok = await coach.submitApplication(
            fullName: fullName,
            email: email,
            credentials: credentials,
            specialties: specialties,
            experienceYears: experienceYears,
            bio: bio,
            website: website,
            social: social
        )
        submitting = false
        if ok {
            Haptics.success()
            withAnimation(.spring(response: 0.35)) { didSubmit = true }
        } else if coach.lastError == nil {
            localError = "Couldn't submit application. Please try again."
        }
    }
}
