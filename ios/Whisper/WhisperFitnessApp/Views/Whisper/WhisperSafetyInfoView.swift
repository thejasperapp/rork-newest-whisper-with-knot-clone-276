import SwiftUI

/// In-app explanation of reviewed decisions, identity, and protection limits.
struct WhisperSafetyInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private struct SafetyProtocol: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let body: [String]
    }

    private var protocols: [SafetyProtocol] {
        [
            SafetyProtocol(
                icon: "siren.fill",
                iconColor: Color(red: 0.91, green: 0.27, blue: 0.20),
                title: "Reviewed post corrections",
                body: [
                    "A correction belongs to a reviewed public post, not a person's reputation. Authorized human reviewers must explain the decision and provide sources. Opinions, satire, uncertainty, AI findings, and report counts are not proof of wrongdoing.",
                    "Notices retain the reviewed version after edits. Authors can revisit and appeal decisions in Settings → Decisions & appeals. Notices can be updated or withdrawn. Historical appeals stay private, not new findings.",
                ]
            ),
            SafetyProtocol(
                icon: "checkmark.seal.fill",
                iconColor: Color(red: 0.13, green: 0.55, blue: 0.96),
                title: "Identity and professional roles",
                body: [
                    "Names show at most one identity or staff indicator. It does not guarantee safety, professional competence, or that a claim is correct. Professional roles are plain profile details; age and membership are not public badges.",
                    "Application reviews, paid tools, and billing remain separate from identity indicators.",
                ]
            ),
            SafetyProtocol(
                icon: "banknote.fill",
                iconColor: Color(red: 0.13, green: 0.65, blue: 0.36),
                title: "Payment protection",
                body: [
                    "Coaching payments run through Stripe — Whisper never sees or stores card numbers. Coaching is billed as a simple monthly subscription: cancel anytime from Settings and you keep access through the end of the month you've paid for. Coaches only receive payouts through bank accounts verified by Stripe.",
                ]
            ),
            SafetyProtocol(
                icon: "flag.fill",
                iconColor: Color(red: 0.97, green: 0.45, blue: 0.30),
                title: "Reports & moderation",
                body: [
                    "Reports require a confirmed submission. If confirmation fails, retry rather than assuming the report arrived. Reports and reporter details are private to the reporter and authorized reviewers. Repeated reports are not repeated strikes.",
                    "Shared server rules check direct-message sends, including attachments. Blocks and active restrictions take priority over contact permissions. Adult-to-teen first contact requires explicit recipient permission; a previous message alone is not consent. Unknown age is not an automatic exception. Age is self-declared, not independently verified.",
                ]
            ),
            SafetyProtocol(
                icon: "lock.fill",
                iconColor: Color(red: 0.45, green: 0.35, blue: 0.95),
                title: "Your data",
                body: [
                    "Private-account post records require approval. Fitness profile access is limited to you and an accepted coach. Muted words filter your local display; they do not remove content from the platform.",
                    "Blocking and privacy settings cannot recall downloaded files, screenshots, or media shared through public asset links. Ghost mode is not a guarantee of anonymity. Group contact, notifications, and private-media boundaries still need broader live verification.",
                ]
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Hero
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(WhisperTheme.ink(colorScheme))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "shield.checkered")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                            }
                            Text("Safety on Whisper")
                                .font(.largeTitle.weight(.black))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text("Honest progress needs an honest community.")
                                .font(.subheadline)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        .padding(.top, 12)

                        Text("Clear decisions, private reporting, and practical controls—not public reputation scores. Here is what the current protections cover, and where their limits matter.")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)

                        // Protocol cards
                        ForEach(protocols) { proto in
                            protocolCard(proto)
                        }
                        Color.clear.frame(height: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Safety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func protocolCard(_ proto: SafetyProtocol) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(proto.iconColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: proto.icon)
                        .font(.body.weight(.bold))
                        .foregroundStyle(proto.iconColor)
                }
                Text(proto.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            ForEach(proto.body.indices, id: \.self) { i in
                Text(proto.body[i])
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }
}
