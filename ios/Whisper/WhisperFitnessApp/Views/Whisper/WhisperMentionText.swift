import SwiftUI
import Foundation

/// Notification fired when a user taps an `@username` mention anywhere
/// in the app. `WhisperRootView` listens and presents the matching user
/// profile sheet over the current tab.
extension Notification.Name {
    static let whisperOpenUserByUsername = Notification.Name("WhisperOpenUserByUsername")
    /// Fired when tapping an avatar whose owner has an active story so the
    /// root view can present the story viewer over the current tab.
    /// `userInfo["storyID"]` carries the target row id.
    static let whisperOpenStory = Notification.Name("WhisperOpenStory")
    /// Fired after a comment lands on the server so every mounted card for
    /// that post can bump its count immediately. `userInfo["postID"]` is the
    /// lowercased post id.
    static let whisperCommentPosted = Notification.Name("WhisperCommentPosted")
}

/// Detects `@handle` and `#hashtag` tokens in a string. Handles are
/// case-insensitive, must be a whole-word boundary so prefixes like
/// `email@foo.com` aren't treated as mentions, and may contain letters,
/// numbers, underscores and dots.
enum WhisperMentionParser {
    struct Token: Hashable {
        let range: Range<String.Index>
        let kind: Kind
        /// The handle/hashtag text WITHOUT the `@`/`#` prefix.
        let value: String
        enum Kind { case mention, hashtag }
    }

    private static let mentionChars = CharacterSet.letters
        .union(.decimalDigits)
        .union(CharacterSet(charactersIn: "_."))

    static func tokens(in s: String) -> [Token] {
        var out: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            guard c == "@" || c == "#" else {
                i = s.index(after: i)
                continue
            }
            // Boundary check: previous char must be whitespace/punctuation
            // (anything that isn't alphanumeric) so e.g. `user@host.com`
            // doesn't trigger.
            if i > s.startIndex {
                let prev = s[s.index(before: i)]
                if prev.isLetter || prev.isNumber || prev == "_" {
                    i = s.index(after: i)
                    continue
                }
            }
            var j = s.index(after: i)
            var captured: [Character] = []
            while j < s.endIndex {
                let cj = s[j]
                if cj.isLetter || cj.isNumber || cj == "_" || cj == "." {
                    captured.append(cj)
                    j = s.index(after: j)
                } else {
                    break
                }
            }
            guard !captured.isEmpty else {
                i = s.index(after: i)
                continue
            }
            // Trim trailing dot — `@bob.` shouldn't include the period.
            while captured.last == "." {
                captured.removeLast()
                j = s.index(before: j)
            }
            guard !captured.isEmpty else {
                i = s.index(after: i)
                continue
            }
            let kind: Token.Kind = (c == "@") ? .mention : .hashtag
            out.append(Token(range: i..<j, kind: kind, value: String(captured)))
            i = j
        }
        return out
    }

    /// All `@handles` found in `s`, lowercased and de-duplicated.
    static func mentions(in s: String) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for t in tokens(in: s) where t.kind == .mention {
            let key = t.value.lowercased()
            if seen.insert(key).inserted { out.append(t.value) }
        }
        return out
    }
}

/// Renders a string with `@username` and `#hashtag` tokens tinted in the
/// app accent and tappable. Drop-in replacement for `Text(rawString)`.
///
/// Taps post `.whisperOpenUserByUsername` (or `.whisperOpenHashtag`) so
/// any host surface can present the right destination. We use a custom
/// `whisperuser://` / `whispertag://` URL on each tinted run and route
/// it through an environment `openURL` handler.
struct WhisperMentionText: View {
    let text: String
    var font: Font = .subheadline
    var weight: Font.Weight = .regular
    var lineLimit: Int? = nil
    /// Optional leading bold username (Instagram caption style) — rendered
    /// semibold in ink, followed by a space, before the linkified body.
    var boldPrefix: String? = nil
    /// Overrides the theme ink for surfaces that sit on media (the Waves
    /// player's caption is always white on video, whatever the color scheme).
    var inkColor: Color? = nil
    /// Overrides the mention / hashtag tint (defaults to the brand accent).
    var linkColor: Color? = nil
    /// Makes ordinary post text open its discussion without intercepting mention links.
    var onOpenPost: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private var ink: Color { inkColor ?? WhisperTheme.ink(colorScheme) }

    var body: some View {
        Text(attributed)
            .font(font.weight(weight))
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: lineLimit == nil)
            .environment(\.openURL, OpenURLAction { url in
                guard let scheme = url.scheme?.lowercased() else { return .systemAction }
                if scheme == "whisperpost", let onOpenPost {
                    onOpenPost()
                    return .handled
                }
                if scheme == "whisperuser" {
                    let handle = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if !handle.isEmpty {
                        NotificationCenter.default.post(
                            name: .whisperOpenUserByUsername,
                            object: nil,
                            userInfo: ["username": handle]
                        )
                        Haptics.tap()
                    }
                    return .handled
                }
                openURL(url)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var attr = AttributedString(stringLiteral: text)
        attr.foregroundColor = ink
        if onOpenPost != nil {
            attr.link = URL(string: "whisperpost://open")
            attr.underlineStyle = .none
        }
        let tokens = WhisperMentionParser.tokens(in: text)
        for token in tokens {
            // Map String.Index → AttributedString.Index via UTF-16 offsets.
            let lower = text.utf16.distance(from: text.startIndex, to: token.range.lowerBound)
            let upper = text.utf16.distance(from: text.startIndex, to: token.range.upperBound)
            guard
                let lowerIdx = AttributedString.Index(
                    String.Index(utf16Offset: lower, in: text),
                    within: attr
                ),
                let upperIdx = AttributedString.Index(
                    String.Index(utf16Offset: upper, in: text),
                    within: attr
                )
            else { continue }
            let range = lowerIdx..<upperIdx
            attr[range].foregroundColor = linkColor ?? WhisperTheme.accent
            attr[range].font = font.weight(.semibold)
            switch token.kind {
            case .mention:
                if let url = URL(string: "whisperuser://\(token.value)") {
                    attr[range].link = url
                }
            case .hashtag:
                // No destination wired yet — keep visual tint but no link
                // so taps don't escape into Safari.
                break
            }
        }
        if let prefix = boldPrefix, !prefix.isEmpty {
            var head = AttributedString(prefix + " ")
            head.font = font.weight(.semibold)
            head.foregroundColor = ink
            return head + attr
        }
        return attr
    }
}

extension WhisperTheme {
    /// Brand accent used for mentions, hashtags, and other linkified inline
    /// tokens. Falls back to the system accent if a richer brand color
    /// isn't defined.
    static let accent: Color = Color(red: 0.20, green: 0.55, blue: 1.0)
}
