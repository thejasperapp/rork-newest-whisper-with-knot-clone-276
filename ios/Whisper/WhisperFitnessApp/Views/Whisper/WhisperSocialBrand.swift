import SwiftUI

/// Maps a URL to a recognized social-media brand so verified featured-link
/// chips show the proper logo instead of a generic link icon. Falls back to
/// `nil` when no brand is recognized — callers then render the user's emoji
/// or the generic link glyph.
enum WhisperSocialBrand: String, CaseIterable, Sendable {
    case instagram, facebook, threads, youtube, tiktok, x, snapchat
    case linkedin, linktree, spotify, appleMusic, twitch, discord
    case pinterest, reddit, github, onlyfans, patreon, substack
    case soundcloud, whatsapp, telegram, beReal, vsco, tumblr

    /// Returns the matching brand, or nil if the host isn't a known social.
    static func detect(from raw: String) -> WhisperSocialBrand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host: String = {
            if let url = URL(string: trimmed.hasPrefix("http") ? trimmed : "https://" + trimmed),
               let h = url.host {
                return h.replacingOccurrences(of: "www.", with: "")
            }
            return trimmed
        }()
        for brand in WhisperSocialBrand.allCases {
            if brand.hosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
                return brand
            }
        }
        return nil
    }

    private var hosts: [String] {
        switch self {
        case .instagram:  return ["instagram.com", "instagr.am"]
        case .facebook:   return ["facebook.com", "fb.com", "fb.me"]
        case .threads:    return ["threads.net", "threads.com"]
        case .youtube:    return ["youtube.com", "youtu.be", "m.youtube.com"]
        case .tiktok:     return ["tiktok.com", "vm.tiktok.com"]
        case .x:          return ["x.com", "twitter.com", "t.co"]
        case .snapchat:   return ["snapchat.com", "snap.com"]
        case .linkedin:   return ["linkedin.com", "lnkd.in"]
        case .linktree:   return ["linktr.ee", "linktree.com"]
        case .spotify:    return ["spotify.com", "open.spotify.com", "spoti.fi"]
        case .appleMusic: return ["music.apple.com"]
        case .twitch:     return ["twitch.tv"]
        case .discord:    return ["discord.com", "discord.gg"]
        case .pinterest:  return ["pinterest.com", "pin.it"]
        case .reddit:     return ["reddit.com", "redd.it"]
        case .github:     return ["github.com"]
        case .onlyfans:   return ["onlyfans.com"]
        case .patreon:    return ["patreon.com"]
        case .substack:   return ["substack.com"]
        case .soundcloud: return ["soundcloud.com"]
        case .whatsapp:   return ["whatsapp.com", "wa.me"]
        case .telegram:   return ["telegram.org", "t.me"]
        case .beReal:     return ["bere.al", "bereal.com"]
        case .vsco:       return ["vsco.co"]
        case .tumblr:     return ["tumblr.com"]
        }
    }

    /// User-facing label shown under the icon in the chip.
    var label: String {
        switch self {
        case .instagram:  return "Instagram"
        case .facebook:   return "Facebook"
        case .threads:    return "Threads"
        case .youtube:    return "YouTube"
        case .tiktok:     return "TikTok"
        case .x:          return "X"
        case .snapchat:   return "Snapchat"
        case .linkedin:   return "LinkedIn"
        case .linktree:   return "Linktree"
        case .spotify:    return "Spotify"
        case .appleMusic: return "Apple Music"
        case .twitch:     return "Twitch"
        case .discord:    return "Discord"
        case .pinterest:  return "Pinterest"
        case .reddit:     return "Reddit"
        case .github:     return "GitHub"
        case .onlyfans:   return "OnlyFans"
        case .patreon:    return "Patreon"
        case .substack:   return "Substack"
        case .soundcloud: return "SoundCloud"
        case .whatsapp:   return "WhatsApp"
        case .telegram:   return "Telegram"
        case .beReal:     return "BeReal"
        case .vsco:       return "VSCO"
        case .tumblr:     return "Tumblr"
        }
    }

    /// Bundled image-asset name when we have a real logo PNG; nil = use SF Symbol.
    private var assetName: String? {
        switch self {
        case .instagram: return "SocialInstagram"
        case .facebook:  return "SocialFacebook"
        case .threads:   return "SocialThreads"
        default:         return nil
        }
    }

    /// SF Symbol fallback when no bundled logo exists.
    private var sfSymbol: String {
        switch self {
        case .youtube:    return "play.rectangle.fill"
        case .tiktok:     return "music.note"
        case .x:          return "xmark"
        case .snapchat:   return "camera.fill"
        case .linkedin:   return "briefcase.fill"
        case .linktree:   return "tree.fill"
        case .spotify:    return "music.note"
        case .appleMusic: return "applelogo"
        case .twitch:     return "gamecontroller.fill"
        case .discord:    return "bubble.left.and.bubble.right.fill"
        case .pinterest:  return "pin.fill"
        case .reddit:     return "bubble.left.fill"
        case .github:     return "chevron.left.forwardslash.chevron.right"
        case .onlyfans:   return "drop.fill"
        case .patreon:    return "p.circle.fill"
        case .substack:   return "newspaper.fill"
        case .soundcloud: return "waveform"
        case .whatsapp:   return "phone.fill"
        case .telegram:   return "paperplane.fill"
        case .beReal:     return "circle.dotted"
        case .vsco:       return "camera.aperture"
        case .tumblr:     return "t.square.fill"
        default:          return "link"
        }
    }

    /// Brand tint used when the SF Symbol fallback is shown.
    private var tint: Color {
        switch self {
        case .youtube:    return Color(red: 1.00, green: 0.00, blue: 0.00)
        case .tiktok:     return Color.black
        case .x:          return Color.black
        case .snapchat:   return Color(red: 1.00, green: 0.99, blue: 0.00)
        case .linkedin:   return Color(red: 0.00, green: 0.47, blue: 0.71)
        case .linktree:   return Color(red: 0.27, green: 0.83, blue: 0.41)
        case .spotify:    return Color(red: 0.11, green: 0.84, blue: 0.38)
        case .appleMusic: return Color(red: 0.98, green: 0.20, blue: 0.40)
        case .twitch:     return Color(red: 0.57, green: 0.31, blue: 0.95)
        case .discord:    return Color(red: 0.35, green: 0.40, blue: 0.95)
        case .pinterest:  return Color(red: 0.90, green: 0.05, blue: 0.18)
        case .reddit:     return Color(red: 1.00, green: 0.27, blue: 0.00)
        case .github:     return Color.black
        case .onlyfans:   return Color(red: 0.00, green: 0.67, blue: 0.93)
        case .patreon:    return Color(red: 1.00, green: 0.27, blue: 0.27)
        case .substack:   return Color(red: 1.00, green: 0.42, blue: 0.21)
        case .soundcloud: return Color(red: 1.00, green: 0.50, blue: 0.00)
        case .whatsapp:   return Color(red: 0.15, green: 0.83, blue: 0.40)
        case .telegram:   return Color(red: 0.15, green: 0.63, blue: 0.92)
        case .beReal:     return Color.black
        case .vsco:       return Color.black
        case .tumblr:     return Color(red: 0.21, green: 0.27, blue: 0.36)
        default:          return Color.gray
        }
    }

    /// Renders the brand icon at the requested point size. Uses the bundled
    /// asset when available, otherwise renders the SF Symbol on a brand-colored
    /// tinted rounded square so it still reads as a logo, not a glyph.
    @ViewBuilder
    func iconView(size: CGFloat) -> some View {
        if let asset = assetName, UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size * 0.22))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(tint)
                Image(systemName: sfSymbol)
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}
