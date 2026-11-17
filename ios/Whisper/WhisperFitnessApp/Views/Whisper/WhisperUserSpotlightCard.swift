import SwiftUI

/// Slim spotlight row for real coach, athlete, and creator accounts in
/// search results. Reads like a premium Threads/Instagram result row — a
/// rounded photo, name with the kind seal, one quiet dot-separated identity
/// line, and an optional live rate on the trailing edge. Colour appears
/// ONLY in the tiny seal; everything else stays in Whisper's black & white
/// language so special accounts feel elevated without shouting.
struct WhisperUserSpotlightCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let user: WhisperUserRow
    let kind: FeaturedKind

    @State private var featured = WhisperFeaturedService.shared
    @State private var rate: WhisperCoachRate?

    private var spotlight: WhisperFeaturedProfile? {
        featured.profileByUsername[user.username.lowercased()]
    }

    /// Live monthly rate only shows for coaches actively accepting payments.
    private var pricedRateCents: Int? {
        guard kind == .coach, let r = rate, r.active, r.acceptingPayments else { return nil }
        return r.monthlyPriceCents
    }

    private var photoURL: URL? {
        if let url = spotlight?.resolvedPhotoURL { return url }
        if let raw = user.profile_image_url, let url = URL(string: raw) { return url }
        return nil
    }

    private var blurb: String {
        spotlight?.paragraphs?.first ?? user.bio ?? ""
    }

    /// "@user · Coach · Tier 1 · Powerlifting" — one quiet line instead of
    /// a stack of bordered chips.
    private var metaLine: String {
        var parts: [String] = ["@\(user.username)", kind.displayLabel]
        if kind == .coach, let tier = spotlight?.tier {
            parts.append("Tier \(tier)")
        }
        if let discipline = spotlight?.discipline, !discipline.isEmpty {
            parts.append(discipline)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            photoPanel
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(user.display_name?.isEmpty == false ? user.display_name ?? user.username : user.username)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Image(systemName: kind.sealIcon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(kind.sealColor, in: Circle())
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                if !blurb.isEmpty {
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 8)
            if let cents = pricedRateCents {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(WhisperBillingService.formatCents(cents))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("per month")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .contentShape(.rect)
        .task(id: user.user_id) {
            // Fold in featured spotlight data + the coach's live monthly
            // rate. Both are cached / cheap; failures just hide the extras.
            let generation = AccountStorage.generation
            _ = await featured.fetchByUsername(user.username)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            if kind == .coach {
                let loaded = try? await WhisperBillingService.shared.fetchCoachRate(coachUserID: user.user_id)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                rate = loaded
            }
        }
    }

    private var photoPanel: some View {
        // Top-anchored crop — portrait spotlight photos keep the face in
        // frame instead of centering on the torso.
        Color(.secondarySystemBackground)
            .frame(width: 52, height: 52)
            .overlay(alignment: .top) {
                if let url = photoURL {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        default:
                            WhisperAvatar(username: user.username, size: 36)
                        }
                    }
                } else {
                    WhisperAvatar(username: user.username, size: 36)
                }
            }
            .clipShape(.rect(cornerRadius: 16))
    }
}
