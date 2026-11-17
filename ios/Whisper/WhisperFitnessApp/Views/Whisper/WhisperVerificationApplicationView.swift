import SwiftUI

/// Public-facing verification application sheet. Users describe who they
/// are, what they create, and submit. The row lands in
/// `whisper_verification_requests` and shows up in the mod dashboard.
struct WhisperVerificationApplicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var service = WhisperVerificationService.shared

    @State private var fullName: String = ""
    @State private var email: String = AuthenticationService.shared.currentUser.email ?? ""
    @State private var category: String = "creator"
    @State private var reason: String = ""
    @State private var links: String = ""
    @State private var followers: String = ""

    @State private var submitting: Bool = false
    @State private var didSubmit: Bool = false

    private let categories: [(id: String, label: String)] = [
        ("creator", "Creator"),
        ("coach", "Coach / Trainer"),
        ("athlete", "Athlete"),
        ("brand", "Brand"),
        ("media", "Media / Publisher"),
        ("public_figure", "Public figure"),
        ("other", "Other")
    ]

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
        && !reason.trimmingCharacters(in: .whitespaces).isEmpty
        && !submitting
        && !service.hasPendingApplication
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hero
                        if service.hasPendingApplication {
                            pendingCard
                        } else if didSubmit {
                            submittedCard
                        } else {
                            perksCard
                            formCard
                            submitButton
                            if let err = service.lastError {
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
            .navigationTitle("Get verified")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task { await service.refreshMyStatus() }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.96))
                Text("Verification")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.96))
            }
            Text("Apply for the blue check")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Verification confirms you are who you say you are. We grant it to creators, coaches, athletes, brands, and public figures with a real public presence.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    // MARK: - Perks

    private var perksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you get")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            ForEach(WhisperVerifiedPerks.perks, id: \.self) { perk in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.96))
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

    // MARK: - Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Legal name", placeholder: "Full name", text: $fullName)
            field("Email", placeholder: "you@example.com", text: $email, keyboard: .emailAddress)
            categoryPicker
            field("Total followers across platforms", placeholder: "e.g. 25000", text: $followers, keyboard: .numberPad)
            multilineField("Why should you be verified?", text: $reason, placeholder: "Tell us about your work, audience, and what people search for you on.")
            multilineField("Links (one per line)", text: $links, placeholder: "https://instagram.com/you\nhttps://yoursite.com")
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
    }

    private func multilineField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                }
                TextEditor(text: text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Category").font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.id) { c in
                        Button {
                            Haptics.tap()
                            category = c.id
                        } label: {
                            Text(c.label)
                                .font(.footnote.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    category == c.id
                                    ? WhisperTheme.ink(colorScheme)
                                    : WhisperTheme.surface(colorScheme),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    category == c.id
                                    ? WhisperTheme.surface(colorScheme)
                                    : WhisperTheme.ink(colorScheme)
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
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Haptics.tap()
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().tint(WhisperTheme.surface(colorScheme)) }
                Text(submitting ? "Submitting…" : "Submit application")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                canSubmit ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme),
                in: Capsule()
            )
            .foregroundStyle(WhisperTheme.surface(colorScheme))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var disclaimer: some View {
        Text("Applications are reviewed by Whisper moderators. We'll notify you here when there's an update.")
            .font(.caption)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 4)
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.96))
                Text("Under review")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Text("Your application has been received. Reviews typically take 3–7 days.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var submittedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.96))
            Text("Application submitted")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("We'll review and get back to you here.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        let count = Int(followers.filter { $0.isNumber }) ?? 0
        let ok = await service.submit(
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.isEmpty ? nil : email,
            category: category,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            links: links.isEmpty ? nil : links,
            followers: count
        )
        if ok {
            Haptics.success()
            didSubmit = true
        } else {
            Haptics.warning()
        }
    }
}
