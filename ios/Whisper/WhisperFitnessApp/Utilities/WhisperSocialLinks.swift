import SwiftUI

nonisolated enum WhisperSocialLinks {
    static let threads: URL = URL(string: "https://www.threads.com/@thejasperapp")!
    static let instagram: URL = URL(string: "https://www.instagram.com/thejasperapp")!
    static let facebook: URL = URL(string: "https://www.facebook.com/profile.php?id=61582235167205")!
}

// MARK: - Brand glyphs (real platform marks bundled as image assets)

/// Real Instagram brand mark (asset).
struct InstagramGlyph: View {
    var color: Color = .black

    var body: some View {
        Image("SocialInstagram")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
    }
}

/// Real Threads brand mark (asset).
struct ThreadsGlyph: View {
    var color: Color = .black

    var body: some View {
        Image("SocialThreads")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
    }
}

/// Real Facebook brand mark (asset).
struct FacebookGlyph: View {
    var color: Color = .black
    var inverted: Bool = false

    var body: some View {
        Image("SocialFacebook")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
    }
}

// MARK: - Rows

struct WhisperSocialRow: View {
    var tint: Color = .primary
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: 14) {
            button(url: WhisperSocialLinks.instagram, label: "Instagram") {
                InstagramGlyph(color: .black)
            }
            button(url: WhisperSocialLinks.threads, label: "Threads") {
                ThreadsGlyph(color: .black)
            }
            button(url: WhisperSocialLinks.facebook, label: "Facebook") {
                FacebookGlyph(color: .black)
            }
        }
    }

    private func button<Glyph: View>(url: URL, label: String, @ViewBuilder glyph: () -> Glyph) -> some View {
        Link(destination: url) {
            glyph()
                .frame(width: size, height: size)
                .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
    }
}

struct WhisperSocialFooter: View {
    var label: String = "Follow Whisper"
    var tint: Color = .primary

    private let size: CGFloat = 28

    var body: some View {
        VStack(spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                button(url: WhisperSocialLinks.instagram, label: "Instagram") {
                    InstagramGlyph(color: .black)
                }
                button(url: WhisperSocialLinks.threads, label: "Threads") {
                    ThreadsGlyph(color: .black)
                }
                button(url: WhisperSocialLinks.facebook, label: "Facebook") {
                    FacebookGlyph(color: .black)
                }
            }
        }
    }

    private func button<Glyph: View>(url: URL, label: String, @ViewBuilder glyph: () -> Glyph) -> some View {
        Link(destination: url) {
            glyph()
                .frame(width: size, height: size)
                .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
    }
}
