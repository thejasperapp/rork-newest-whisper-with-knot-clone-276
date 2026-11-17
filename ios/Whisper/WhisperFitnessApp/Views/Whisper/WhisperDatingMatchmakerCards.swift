import SwiftUI

/// Jasper's matchmaker RESPONSE SYSTEM — the brain answers in a strict
/// grammar (READ / MATCH / MOVE) and the dock renders it as real cards:
/// one tappable card per match with why-we-click and a ready opener, a
/// one-line read on top, and the concrete next move underneath. Anything
/// that doesn't parse falls back to the plain reply. Mirrors web
/// `lib/matchmakerReply.ts` + `MatchmakerCards` exactly.
enum WhisperMatchmakerReply {
    struct Match: Identifiable {
        let username: String
        let why: String
        let opener: String
        var id: String { username.lowercased() }
    }

    struct Parsed {
        let read: String?
        let matches: [Match]
        let move: String?
    }

    /// The strict-format instruction every matchmaker lens ends with.
    static let format = """
    Reply in EXACTLY this format and nothing else:
    READ: <one honest line about me or the room right now>
    MATCH: @username | <why we click — one line grounded in their actual words> | <a say-hi opener in first person, one line, specific>
    MATCH: @username | <why> | <opener>
    MOVE: <the one concrete thing I should do next — one line>
    Use only people who appear in the context. If nobody fits yet, give no MATCH lines and make MOVE the honest next step.
    """

    /// nil when no MATCH/READ/MOVE structure is present — render plain text.
    static func parse(_ text: String) -> Parsed? {
        var read: String? = nil
        var move: String? = nil
        var matches: [Match] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*-• "))
            let upper = line.uppercased()
            if upper.hasPrefix("READ:") {
                read = clean(String(line.dropFirst(5)))
            } else if upper.hasPrefix("MOVE:") {
                move = clean(String(line.dropFirst(5)))
            } else if upper.hasPrefix("MATCH:") {
                let body = String(line.dropFirst(6))
                let parts = body.components(separatedBy: "|").map { clean($0) }
                guard let handle = parts.first, !handle.isEmpty else { continue }
                let username = handle
                    .replacingOccurrences(of: "@", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "*_ "))
                guard !username.isEmpty else { continue }
                matches.append(Match(
                    username: username,
                    why: parts.count > 1 ? parts[1] : "",
                    opener: parts.count > 2 ? parts[2] : ""
                ))
            }
        }
        guard read != nil || move != nil || !matches.isEmpty else { return nil }
        return Parsed(read: read, matches: Array(matches.prefix(3)), move: move)
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“” "))
    }
}

/// The parsed matchmaker reply as cards inside the dock's glass box.
struct WhisperMatchmakerCardsView: View {
    let parsed: WhisperMatchmakerReply.Parsed
    let accent: Color
    let softAccent: Color
    /// Resolves a handle to an avatar URL when the hub knows it.
    let avatarFor: (String) -> URL?
    let onSayHi: (WhisperMatchmakerReply.Match) -> Void

    @State private var copied: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let read = parsed.read, !read.isEmpty {
                Text(read)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if parsed.matches.isEmpty {
                Text("No clear match in the hub yet — the move below is the play.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
            ForEach(parsed.matches) { match in
                matchCard(match)
            }
            if let move = parsed.move, !move.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Text("🎯")
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YOUR MOVE")
                            .font(.system(size: 8.5, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(softAccent)
                        Text(move)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
            }
        }
    }

    private func matchCard(_ match: WhisperMatchmakerReply.Match) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(accent.opacity(0.35))
                    if let url = avatarFor(match.username) {
                        WhisperCachedAsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.clear
                            }
                        }
                    } else {
                        Text(String(match.username.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(softAccent.opacity(0.7), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(match.username)")
                        .font(.system(size: 13.5, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Suggested connection")
                        .font(.caption)
                        .foregroundStyle(softAccent)
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    if !match.opener.isEmpty {
                        UIPasteboard.general.string = match.opener
                        withAnimation(.easeOut(duration: 0.2)) { copied = match.id }
                    }
                    onSayHi(match)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.wave.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Say hi")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
            if !match.why.isEmpty {
                Text(match.why)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !match.opener.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Rectangle()
                        .fill(softAccent)
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(match.opener)”")
                            .font(.system(size: 12, weight: .semibold))
                            .italic()
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(copied == match.id ? "Copied — paste it in the chat" : "Tap Say hi — the opener copies for you")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.35), lineWidth: 1))
    }
}
