import SwiftUI
import UIKit

/// Whisper-branded share sheet. Replaces the system `UIActivityViewController`
/// with a custom card that shows the user's @handle, an invite preview, and
/// a row of channels (copy link, message, system share, QR). Wired to real
/// behavior — every option does something.
struct WhisperShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let username: String

    @State private var copied: Bool = false
    @State private var presentSystemShare: Bool = false
    @State private var presentNewMessageSheet: Bool = false
    @State private var dmTarget: WhisperShareDMTarget? = nil
    @State private var sendingProfile: Bool = false
    @State private var profileSentToast: Bool = false

    private struct WhisperShareDMTarget: Identifiable {
        let id = UUID()
        let userID: String
        let username: String
    }

    /// Public desktop profile link — mirrors the web app's `/p/:username`
    /// route so anyone (signed in or not) can open the shared profile.
    private var inviteURL: String {
        let handle = username
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return "https://mydailywhisper.com/p/\(handle)"
    }
    private var inviteText: String { "Follow me on Whisper — \(username)\n\(inviteURL)" }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        previewCard
                        channelsRow
                        VStack(spacing: 0) {
                            actionRow(icon: "link", title: "Copy link", subtitle: inviteURL) { copyLink() }
                            divider
                            actionRow(icon: "message.fill", title: "Send in Messages", subtitle: "iMessage / SMS") { openMessages() }
                            divider
                            actionRow(icon: "square.and.arrow.up", title: "More options", subtitle: "System share sheet") { presentSystemShare = true }
                        }
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        WhisperWordmark(size: 22)
                        Text("Share")
                            .font(.headline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .overlay(alignment: .top) {
                if copied {
                    Text("Link copied")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if profileSentToast {
                    HStack(spacing: 6) {
                        if sendingProfile {
                            ProgressView()
                                .tint(WhisperTheme.surface(colorScheme))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold))
                        }
                        Text(sendingProfile ? "Sending profile…" : "Profile sent in DM")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $presentSystemShare) {
                ShareSheet(items: [inviteText])
            }
            .sheet(isPresented: $presentNewMessageSheet) {
                WhisperNewMessageSheet { userID, username in
                    presentNewMessageSheet = false
                    Task { await sendProfileCard(toUserID: userID, toUsername: username) }
                }
            }
            .fullScreenCover(item: $dmTarget) { target in
                WhisperDMThreadView(otherUserID: target.userID, otherUsername: target.username)
            }
        }
    }

    // MARK: - Preview card

    private var previewCard: some View {
        VStack(spacing: 16) {
            WhisperAvatar(username: username, size: 84, ring: true)
            VStack(spacing: 4) {
                Text(username)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("on Whisper")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Text(inviteURL)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(WhisperTheme.surface(colorScheme), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var channelsRow: some View {
        HStack(spacing: 10) {
            channel(icon: "doc.on.doc", label: "Copy") { copyLink() }
            channel(icon: "bubble.left.fill", label: "Whisper DM") { openWhisperDM() }
            channel(icon: "envelope.fill", label: "Mail") { openMail() }
            channel(icon: "square.and.arrow.up", label: "More") { presentSystemShare = true }
        }
    }

    private func channel(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 56, height: 56)
                    .background(WhisperTheme.ink(colorScheme), in: Circle())
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    private func actionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func copyLink() {
        UIPasteboard.general.string = inviteURL
        Haptics.success()
        withAnimation(.spring(response: 0.3)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { copied = false }
        }
    }

    private func openWhisperDM() {
        presentNewMessageSheet = true
    }

    /// Fetches the sender's full public profile, encodes it as a
    /// `WhisperProfileShareEmbed`, and sends it as a rich card in a new
    /// DM thread — so the recipient sees a tappable profile preview, not
    /// just a bare text link.
    private func sendProfileCard(toUserID: String, toUsername: String) async {
        let myID = AccountStorage.currentUserID
        guard myID != "guest", !myID.hasPrefix("local_") else {
            dmTarget = WhisperShareDMTarget(userID: toUserID, username: toUsername)
            return
        }
        await MainActor.run { sendingProfile = true }
        let profile = await WhisperBackendService.shared.fetchPublicProfile(userID: myID)
        let payload: WhisperProfileShareEmbed.Payload
        if let profile {
            payload = WhisperProfileShareEmbed.make(userID: myID, profile: profile)
        } else {
            // Fallback: build from the username we already know.
            payload = WhisperProfileShareEmbed.Payload(
                userID: myID,
                username: username,
                displayName: nil,
                bio: nil,
                avatarURL: nil,
                isVerified: false,
                shareURL: inviteURL
            )
        }
        let body = WhisperProfileShareEmbed.encode(payload)
        if !body.isEmpty {
            _ = await WhisperBackendService.shared.sendMessage(
                toUserID: toUserID,
                toUsername: toUsername,
                body: body
            )
        }
        await MainActor.run {
            sendingProfile = false
            withAnimation(.spring(response: 0.3)) { profileSentToast = true }
        }
        try? await Task.sleep(for: .seconds(1.2))
        await MainActor.run {
            withAnimation { profileSentToast = false }
            dmTarget = WhisperShareDMTarget(userID: toUserID, username: toUsername)
        }
    }

    private func openMessages() {
        let body = inviteText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:&body=\(body)") {
            UIApplication.shared.open(url)
        }
    }

    private func openMail() {
        let subject = "Join me on Whisper".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = inviteText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:?subject=\(subject)&body=\(body)") {
            UIApplication.shared.open(url)
        }
    }
}
