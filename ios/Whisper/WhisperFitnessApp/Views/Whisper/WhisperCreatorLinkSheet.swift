import SwiftUI

/// Creator link & invite code sheet — shows the user's shareable code, the
/// web signup link, and how many signups they've been credited for.
struct WhisperCreatorLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var referrals = WhisperReferralService.shared
    @State private var copiedCode: Bool = false
    @State private var copiedLink: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        if let code = referrals.myCode {
                            codeCard(code.code)
                            statsCard
                            shareCard
                        } else if referrals.isLoading {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .padding(.top, 40)
                        } else if let err = referrals.lastError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 24)
                        }
                        howItWorks
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Creator link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await referrals.refresh() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 72, height: 72)
                .background(WhisperTheme.card(colorScheme), in: Circle())
                .overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            Text("Grow Whisper, get credit")
                .font(.title3.weight(.black))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Share your code or link — every signup that uses it is credited to you.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 12)
    }

    private func codeCard(_ code: String) -> some View {
        Button {
            UIPasteboard.general.string = code
            copiedCode = true
            Haptics.success()
            Task {
                try? await Task.sleep(for: .seconds(2))
                copiedCode = false
            }
        } label: {
            VStack(spacing: 6) {
                Text("YOUR CODE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .kerning(1.2)
                Text(code)
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .kerning(4)
                HStack(spacing: 4) {
                    Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.bold))
                    Text(copiedCode ? "Copied" : "Tap to copy")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(WhisperTheme.ink(colorScheme).opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            }
        }
        .buttonStyle(.plain)
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                Text("\(max(referrals.signupCount, referrals.myCode?.uses ?? 0))")
                    .font(.title2.weight(.black).monospacedDigit())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("signups credited")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .frame(maxWidth: .infinity)
            Rectangle()
                .fill(WhisperTheme.hairline(colorScheme))
                .frame(width: 1, height: 36)
            VStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("counts toward roles")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var shareCard: some View {
        if let link = referrals.shareLink, let url = URL(string: link) {
            VStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = link
                    copiedLink = true
                    Haptics.success()
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedLink = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        Text(link.replacingOccurrences(of: "https://", with: ""))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .padding(12)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                ShareLink(
                    item: url,
                    message: Text("Join me on Whisper — use my code \(referrals.myCode?.code ?? "") when you sign up.")
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share your link")
                            .font(.body.weight(.bold))
                    }
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 14))
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            }
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW IT WORKS")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .kerning(0.6)
            step(1, "Share your code or link with friends, followers, or clients.")
            step(2, "They enter it during signup (the link prefills it for them).")
            step(3, "Every signup is credited to you — watch your count climb.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.black))
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(width: 20, height: 20)
                .background(WhisperTheme.ink(colorScheme), in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.9))
        }
    }
}
