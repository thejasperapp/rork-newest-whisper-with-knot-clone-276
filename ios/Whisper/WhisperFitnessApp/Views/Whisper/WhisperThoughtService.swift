import SwiftUI
import UIKit
import AVFoundation
import Supabase

// MARK: - Supabase schema (idempotent — safe to re-run)
//
// create table if not exists public.whisper_thoughts (
//   user_id uuid primary key references auth.users(id) on delete cascade,
//   text text not null,
//   posted_at timestamptz not null default now(),
//   updated_at timestamptz not null default now()
// );
// alter table public.whisper_thoughts add column if not exists style  text;
// alter table public.whisper_thoughts add column if not exists accent text;
// alter table public.whisper_thoughts add column if not exists emoji  text;
// alter table public.whisper_thoughts add column if not exists color_hex text;
// alter table public.whisper_thoughts enable row level security;
// drop policy if exists "wth read all"    on public.whisper_thoughts;
// create policy "wth read all"    on public.whisper_thoughts for select using (true);
// drop policy if exists "wth upsert own"  on public.whisper_thoughts;
// create policy "wth upsert own"  on public.whisper_thoughts for insert with check (auth.uid() = user_id);
// drop policy if exists "wth update own"  on public.whisper_thoughts;
// create policy "wth update own"  on public.whisper_thoughts for update using (auth.uid() = user_id);
// drop policy if exists "wth delete own"  on public.whisper_thoughts;
// create policy "wth delete own"  on public.whisper_thoughts for delete using (auth.uid() = user_id);

/// Visual treatment for a thought bubble. `plain` = white IG-Notes look.
/// `location` = hot-pink pill with a map-pin glyph and the user's city.
/// `music` = purple pill with a music-note glyph and "Title — Artist".
nonisolated enum WhisperThoughtStyle: String, Codable, Sendable, CaseIterable {
    case plain
    case location
    case music
}

nonisolated struct WhisperThoughtUpsert: Codable, Sendable {
    let user_id: String
    let text: String
    let posted_at: String
    let style: String?
    let accent: String?
    let emoji: String?
    let color_hex: String?

    // Supabase column is named `body` (not `text`) — map at the wire level.
    enum CodingKeys: String, CodingKey {
        case user_id
        case text = "body"
        case posted_at
        case style
        case accent
        case emoji
        case color_hex
    }
}

nonisolated struct WhisperThoughtRow: Codable, Sendable {
    let user_id: String
    let text: String
    let posted_at: String?
    let style: String?
    let accent: String?
    let emoji: String?
    let color_hex: String?

    enum CodingKeys: String, CodingKey {
        case user_id
        case text = "body"
        case posted_at
        case style
        case accent
        case emoji
        case color_hex
    }
}

/// "Sharing thoughts" feature — Whisper's take on Instagram/Threads notes.
/// The user taps the `+` on their avatar, types a short line, and it floats
/// in a chat-bubble above their profile picture and story for 24 hours.
///
/// Thoughts are written-through to `whisper_thoughts` on Supabase so they
/// follow the user across devices and survive a reinstall. UserDefaults
/// stays as the local cache so the bubble renders instantly on cold start
/// before the network round-trip resolves.
@MainActor
@Observable
final class WhisperThoughtService {
    static let shared = WhisperThoughtService()

    private let textKey = "whisper.thought.text"
    private let dateKey = "whisper.thought.date"
    private let styleKey  = "whisper.thought.style"
    private let accentKey = "whisper.thought.accent"
    private let emojiKey  = "whisper.thought.emoji"
    private let colorKey  = "whisper.thought.colorHex"
    private let client = SupabaseService.shared.client

    var text: String = ""
    var postedAt: Date?
    /// Visual treatment for the bubble (plain / location / music).
    var style: WhisperThoughtStyle = .plain
    /// Secondary line for styled bubbles — e.g. "Miami, FL" or "Song — Artist".
    var accent: String = ""
    /// Optional emoji rendered as a corner badge on the bubble.
    var emoji: String = ""
    /// Optional hex (e.g. `#A855F7`) overriding the bubble's background.
    /// When set, the bubble paints this solid color regardless of `style`.
    var colorHex: String = ""

    /// Hard cap matches Threads' note feature so the bubble never overflows.
    let maxLength = 60

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {
        reloadFromDefaults()
    }

    /// Re-reads the cached thought from `UserDefaults`. Used after the auth
    /// layer wipes account-scoped keys on sign-in / sign-out so the in-memory
    /// singleton stays in sync with what's actually persisted.
    func reloadFromDefaults() {
        text = UserDefaults.standard.string(forKey: textKey) ?? ""
        postedAt = UserDefaults.standard.object(forKey: dateKey) as? Date
        if let raw = UserDefaults.standard.string(forKey: styleKey),
           let parsed = WhisperThoughtStyle(rawValue: raw) {
            style = parsed
        } else {
            style = .plain
        }
        accent = UserDefaults.standard.string(forKey: accentKey) ?? ""
        emoji = UserDefaults.standard.string(forKey: emojiKey) ?? ""
        colorHex = UserDefaults.standard.string(forKey: colorKey) ?? ""
    }

    var isActive: Bool {
        guard let postedAt else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Date().timeIntervalSince(postedAt) < 24 * 3600
    }

    var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Kit 4.0 ghost copy — the real Figma file's empty bubble reads "Note...".
        return trimmed.isEmpty ? "Note..." : trimmed
    }

    func post(
        _ newText: String,
        style: WhisperThoughtStyle = .plain,
        accent: String = "",
        emoji: String = "",
        colorHex: String = ""
    ) {
        let trimmed = String(newText.prefix(maxLength))
        self.text = trimmed
        self.postedAt = Date()
        self.style = style
        self.accent = String(accent.prefix(80))
        self.emoji = String(emoji.prefix(8))
        self.colorHex = String(colorHex.prefix(9))
        UserDefaults.standard.set(text, forKey: textKey)
        UserDefaults.standard.set(postedAt, forKey: dateKey)
        UserDefaults.standard.set(style.rawValue, forKey: styleKey)
        UserDefaults.standard.set(self.accent, forKey: accentKey)
        UserDefaults.standard.set(self.emoji, forKey: emojiKey)
        UserDefaults.standard.set(self.colorHex, forKey: colorKey)
        UserDefaults.standard.synchronize()
        syncWidget()
        // Write-through to Supabase so the thought persists across devices.
        // Failures are silent — the local cache still drives the bubble.
        let snapStyle = style
        let snapAccent = self.accent
        let snapEmoji = self.emoji
        let snapColor = self.colorHex
        Task { [trimmed, postedAt] in
            await self.pushRemote(
                text: trimmed,
                postedAt: postedAt,
                style: snapStyle,
                accent: snapAccent,
                emoji: snapEmoji,
                colorHex: snapColor
            )
        }
    }

    func clear() {
        text = ""
        postedAt = nil
        style = .plain
        accent = ""
        emoji = ""
        colorHex = ""
        UserDefaults.standard.removeObject(forKey: textKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
        UserDefaults.standard.removeObject(forKey: styleKey)
        UserDefaults.standard.removeObject(forKey: accentKey)
        UserDefaults.standard.removeObject(forKey: emojiKey)
        UserDefaults.standard.removeObject(forKey: colorKey)
        syncWidget()
        Task { await self.deleteRemote() }
    }

    // MARK: - Supabase sync

    /// Pulls the most recent thought for the current user from Supabase.
    /// Reconciles with the local cache: if the remote thought is newer than
    /// the local one we adopt it; if the remote thought has expired (>24h)
    /// we clear locally so the bubble disappears across devices.
    func refreshFromServer() async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        do {
            let rows: [WhisperThoughtRow] = try await client
                .from("whisper_thoughts")
                .select("user_id,body,posted_at,style,accent,emoji,color_hex")
                .eq("user_id", value: currentUID)
                .limit(1)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  let row = rows.first else { return }
            let remoteDate = WhisperBackendService.parseISO(row.posted_at ?? "")
            let remoteIsNewer: Bool = {
                guard let r = remoteDate else { return false }
                guard let local = postedAt else { return true }
                return r > local
            }()
            if remoteIsNewer {
                text = row.text
                postedAt = remoteDate
                style = WhisperThoughtStyle(rawValue: row.style ?? "") ?? .plain
                accent = row.accent ?? ""
                emoji = row.emoji ?? ""
                colorHex = row.color_hex ?? ""
                UserDefaults.standard.set(text, forKey: textKey)
                UserDefaults.standard.set(postedAt, forKey: dateKey)
                UserDefaults.standard.set(style.rawValue, forKey: styleKey)
                UserDefaults.standard.set(accent, forKey: accentKey)
                UserDefaults.standard.set(emoji, forKey: emojiKey)
                UserDefaults.standard.set(colorHex, forKey: colorKey)
                UserDefaults.standard.synchronize()
                syncWidget()
            }
        } catch {
            // Silent — table may not exist yet on first run.
        }
    }

    private func pushRemote(
        text: String,
        postedAt: Date?,
        style: WhisperThoughtStyle,
        accent: String,
        emoji: String,
        colorHex: String
    ) async {
        guard isRemote, let postedAt else { return }
        let iso = ISO8601DateFormatter().string(from: postedAt)
        let payload = WhisperThoughtUpsert(
            user_id: currentUID,
            text: text,
            posted_at: iso,
            style: style.rawValue,
            accent: accent.isEmpty ? nil : accent,
            emoji: emoji.isEmpty ? nil : emoji,
            color_hex: colorHex.isEmpty ? nil : colorHex
        )
        do {
            try await client
                .from("whisper_thoughts")
                .upsert(payload, onConflict: "user_id")
                .execute()
        } catch {
            // Silent — local cache still drives the UI.
        }
    }

    private func deleteRemote() async {
        guard isRemote else { return }
        do {
            try await client
                .from("whisper_thoughts")
                .delete()
                .eq("user_id", value: currentUID)
                .execute()
        } catch {
            // Silent.
        }
    }

    /// Mirrors the active thought (if any) into the App Group so the
    /// Whisper Note widget renders the latest version on the home screen.
    private func syncWidget() {
        WhisperWidgetSync.writeThought(isActive ? text : nil)
    }

    // MARK: - Other users' thoughts

    /// Cache of other users' most recent thoughts, keyed by lowercased
    /// `user_id`. Populated by `refreshOthers(userIDs:)` whenever the
    /// stories strip / DM inbox renders, so other users' IG-Notes bubbles
    /// can surface above their story avatars on the home + DMs screens.
    private(set) var others: [String: WhisperThoughtRow] = [:]
    private var othersLastFetch: Date?

    /// Returns the active (non-expired, non-empty) thought for another
    /// user, or `nil` if there isn't one. Expiry mirrors the local rule:
    /// thoughts older than 24h drop off automatically.
    func activeThought(forUserID uid: String) -> WhisperThoughtRow? {
        let key = uid.lowercased()
        guard let row = others[key] else { return nil }
        let trimmed = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Be permissive about freshness: if `posted_at` is missing or the
        // server formatted it in a way we can't parse, still surface the
        // bubble. The 24h drop-off is best-effort — better to occasionally
        // show a slightly-stale thought than to silently hide live ones.
        if let posted = WhisperBackendService.parseISO(row.posted_at ?? ""),
           Date().timeIntervalSince(posted) >= 24 * 3600 {
            return nil
        }
        return row
    }

    /// Pulls the latest `whisper_thoughts` rows for the given user IDs and
    /// stores them in `others`. Safe to call repeatedly — debounced by a
    /// 3s time window so the stories strip rerender loop doesn't spam
    /// Supabase. Throws nothing; failures are silent so the UI still works.
    func refreshOthers(userIDs: [String]) async {
        guard isRemote else { return }
        let myID = currentUID.lowercased()
        let ids: [String] = userIDs.compactMap { raw in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !t.isEmpty, t != "guest", !t.hasPrefix("local_"), t != myID else { return nil }
            return t
        }
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return }
        // Simple time-based debounce only — never skip just because the set
        // matches a previous fetch. Other users post new thoughts behind
        // our back and we need to pick those up on every render pass.
        if let last = othersLastFetch, Date().timeIntervalSince(last) < 3 {
            return
        }
        do {
            // Decode into a tolerant [[String: Any]] first so a single
            // malformed row doesn't blank the whole response, and so we
            // can log exactly what Supabase returned.
            let response = try await client
                .from("whisper_thoughts")
                .select("user_id,body,posted_at,style,accent,emoji,color_hex")
                .in("user_id", values: unique)
                .execute()
            let raw = try? JSONSerialization.jsonObject(with: response.data) as? [[String: Any]]
            let rows: [WhisperThoughtRow] = (raw ?? []).compactMap { dict in
                guard let uid = dict["user_id"] as? String,
                      let text = (dict["body"] as? String) ?? (dict["text"] as? String) else { return nil }
                return WhisperThoughtRow(
                    user_id: uid,
                    text: text,
                    posted_at: dict["posted_at"] as? String,
                    style: dict["style"] as? String,
                    accent: dict["accent"] as? String,
                    emoji: dict["emoji"] as? String,
                    color_hex: dict["color_hex"] as? String
                )
            }
            var map = others
            // Drop any cached entries that are now expired so the bubble
            // disappears across devices once the 24h window closes.
            let now = Date()
            for (k, v) in map {
                if let d = WhisperBackendService.parseISO(v.posted_at ?? ""),
                   now.timeIntervalSince(d) >= 24 * 3600 {
                    map.removeValue(forKey: k)
                }
            }
            for r in rows {
                map[r.user_id.lowercased()] = r
            }
            others = map
            othersLastFetch = now
            let returnedIDs = rows.map { $0.user_id.lowercased() }
            print("[Whisper] thoughts.refreshOthers requested=\(unique.count) returned=\(rows.count) cached=\(others.count)")
            print("[Whisper] thoughts.refreshOthers requestedIDs=\(unique)")
            print("[Whisper] thoughts.refreshOthers returnedIDs=\(returnedIDs)")
            if rows.isEmpty && !unique.isEmpty {
                let rawCount = raw?.count ?? -1
                print("[Whisper] thoughts.refreshOthers no decodable rows (raw=\(rawCount)) — likely whisper_thoughts SELECT RLS is not 'using (true)', or no other user has posted a thought via Supabase yet")
                if let raw, !raw.isEmpty {
                    print("[Whisper] thoughts.refreshOthers raw first row: \(raw[0])")
                }
            }
            // Resolve which of the requested users actually have a visible
            // bubble so we can flag the asymmetry — a row may exist but
            // be empty or stale.
            let visible = unique.filter { activeThought(forUserID: $0) != nil }
            print("[Whisper] thoughts.refreshOthers visibleBubbles=\(visible.count)/\(unique.count)")
        } catch {
            print("[Whisper] thoughts.refreshOthers error: \(error.localizedDescription)")
        }
    }
}

/// SwiftUI wrapper around a `UITextField` subclass that overrides
/// `textInputContextIdentifier` to return `"emoji"`. iOS uses that key to
/// remember the last keyboard plane per input context — by giving it a
/// dedicated id and pre-warming the cache, the system pops directly into
/// the emoji keyboard the first time the field becomes first responder.
/// Used by the thought composer so picking an emoji feels native.
struct WhisperEmojiKeyboardField: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.text = text
        field.tintColor = .clear
        field.textColor = .clear
        field.backgroundColor = .clear
        field.keyboardType = .default
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: WhisperEmojiKeyboardField
        init(_ p: WhisperEmojiKeyboardField) { parent = p }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            // Accept only emoji-bearing input — ignore plain ASCII so the
            // user can't accidentally type letters into the badge.
            let containsEmoji = string.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji }
            if string.isEmpty {
                // Allow backspace.
                parent.text = ""
                return false
            }
            guard containsEmoji else { return false }
            parent.text = string
            // Resign on next runloop so the keyboard collapses after the
            // selection lands.
            DispatchQueue.main.async { textField.resignFirstResponder() }
            return false
        }
    }

    /// UITextField subclass that nudges the keyboard cache to default to
    /// the emoji plane.
    final class EmojiTextField: UITextField {
        override var textInputContextIdentifier: String? { "emoji" }
        override var textInputMode: UITextInputMode? {
            for mode in UITextInputMode.activeInputModes {
                if mode.primaryLanguage == "emoji" { return mode }
            }
            return super.textInputMode
        }
    }
}

/// Horizontally auto-scrolling single-line text. If the text fits in the
/// available width it renders statically; otherwise it loops continuously
/// from right to left with a small gap between repetitions — like the
/// "Now playing" ticker on Apple Music / Spotify mini players.
struct WhisperMarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    /// Points the text travels per second when scrolling.
    var speed: Double = 22
    /// Gap between the trailing copy and the wrapped-around copy.
    var gap: CGFloat = 24

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating: Bool = false

    private var needsScroll: Bool {
        textWidth > containerWidth + 0.5 && containerWidth > 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if needsScroll {
                    HStack(spacing: gap) {
                        Text(text).font(font).foregroundStyle(color).fixedSize()
                        Text(text).font(font).foregroundStyle(color).fixedSize()
                    }
                    .offset(x: offset)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .frame(width: geo.size.width, alignment: .leading)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .onAppear {
                containerWidth = geo.size.width
                measureAndStart()
            }
            .onChange(of: geo.size.width) { _, newValue in
                containerWidth = newValue
                measureAndStart()
            }
            .onChange(of: text) { _, _ in
                animating = false
                offset = 0
                measureAndStart()
            }
        }
        .background(
            // Off-screen measuring copy so we know the natural text width.
            Text(text)
                .font(font)
                .fixedSize()
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { textWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, w in textWidth = w }
                    }
                )
        )
        .frame(height: heightForFont)
    }

    private var heightForFont: CGFloat {
        // Approximate single-line height; matches the regular Text layout.
        UIFont.preferredFont(forTextStyle: .footnote).lineHeight
    }

    private func measureAndStart() {
        guard needsScroll, !animating else { return }
        animating = true
        offset = 0
        let distance = textWidth + gap
        let duration = Double(distance) / max(speed, 1)
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}

/// Chat-bubble that floats above an avatar showing the user's current
/// thought — Instagram "Notes" style: a white rounded-rectangle bubble with
/// a soft drop shadow and two stacked circles forming a tail pointing
/// down to the avatar. Designed to be placed as an `.overlay` on top of
/// an avatar so it visually sits *partially on* the profile photo.
/// The kit's notes cloud as ONE unified path — the rounded body, the
/// integrated tail bump ON the bottom edge, and the detached dot below —
/// so the fill flows across the union and shadows trace the composite
/// silhouette exactly like the web bubble's drop-shadow filter.
struct WhisperNotesCloudShape: Shape {
    /// Body corner radius (17.7 × unit, or height/2 for compact pills).
    var corner: CGFloat
    /// The kit unit — bubble height / 41 (the Figma Union's body height).
    var unit: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: corner, height: corner),
            style: .continuous
        )
        // Integrated tail bump — centre sits ON the bottom edge at x = 16
        // in 41-unit body space; its top half hides behind the body.
        let bumpR = 3.93 * unit
        p.addEllipse(in: CGRect(
            x: rect.minX + 16 * unit - bumpR,
            y: rect.maxY - bumpR,
            width: bumpR * 2,
            height: bumpR * 2
        ))
        // Detached 4pt dot at (21, 46) — centre (21, maxY + 5) in body space.
        let dotR = 2 * unit
        p.addEllipse(in: CGRect(
            x: rect.minX + 21 * unit - dotR,
            y: rect.maxY + 5 * unit - dotR,
            width: dotR * 2,
            height: dotR * 2
        ))
        return p
    }
}

struct WhisperThoughtBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    /// Shared note geometry; avatar hosts use 1.0 on both profiles and story rails.
    var scale: CGFloat = 1.0
    /// Visual treatment — plain / location / music.
    var style: WhisperThoughtStyle = .plain
    /// Secondary line for styled bubbles (city for location, song for music).
    /// Ignored when `style == .plain`.
    var accent: String = ""
    /// Emoji rendered as a small corner badge on the top-right of the bubble.
    var emoji: String = ""
    /// Optional hex override (e.g. `#A855F7`). When non-empty, paints the
    /// bubble with this solid color regardless of `style`.
    var colorHex: String = ""

    // MARK: - Style colors

    /// Resolved custom color, if `colorHex` parses cleanly.
    private var customColor: Color? {
        Self.parseHex(colorHex)
    }

    /// Whether the resolved custom color is dark enough to need white text.
    private var customIsDark: Bool {
        Self.luminanceOfHex(colorHex) < 0.62
    }

    /// Approximate perceptual luminance (0..1) of a hex string.
    fileprivate static func luminanceOfHex(_ raw: String) -> Double {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6, let v = UInt64(s.prefix(6), radix: 16) else { return 1 }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >>  8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Background fill / gradient for the bubble depending on style.
    private var bubbleFill: AnyShapeStyle {
        if let c = customColor {
            return AnyShapeStyle(LinearGradient(
                colors: [c, c.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        switch style {
        case .plain, .music:
            // Kit-exact: the note AND the music note are the same flat-white
            // cloud — no gradient, no stroke; the soft shadow does the work.
            return AnyShapeStyle(Color.white)
        case .location:
            // Hot-pink → soft-pink diagonal gradient (Whisper's own variant).
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1.00, green: 0.24, blue: 0.55), Color(red: 1.00, green: 0.45, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
    }

    /// Splits a legacy `"Title — Artist"` accent string into its two parts.
    /// New posts store title in `text` and artist in `accent` directly, but
    /// pre-existing thoughts kept the joined form so we still need to parse it.
    fileprivate static func splitMusicAccent(text: String, accent: String) -> (title: String, artist: String) {
        // New format: text holds the title, accent holds only the artist.
        if text != "Now playing" && !text.isEmpty && !accent.contains("\u{2014}") {
            return (text, accent)
        }
        // Legacy format: accent = "Title — Artist".
        let sep = " \u{2014} "
        if let range = accent.range(of: sep) {
            let title = String(accent[..<range.lowerBound])
            let artist = String(accent[range.upperBound...])
            return (title, artist)
        }
        return (text == "Now playing" ? accent : text, accent == text ? "" : accent)
    }

    private var bubbleText: Color {
        if customColor != nil {
            if let c = Self.complementaryText(forHex: colorHex) { return c }
            return customIsDark ? .white : Color(white: 0.12)
        }
        switch style {
        // Kit: ink text on the white cloud — music included (song 600, artist gray).
        case .plain, .music: return Color(white: 0.12)
        case .location: return .white
        }
    }

    /// Returns a same-hue text color that compliments the bubble background:
    /// a light bg (e.g. lavender) yields a deep version of the same hue,
    /// a dark bg (e.g. royal purple) yields a soft pastel of the same hue.
    /// Neutrals (very low saturation) fall back to plain black/white.
    fileprivate static func complementaryText(forHex raw: String) -> Color? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6, let v = UInt64(s.prefix(6), radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >>  8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &sat, brightness: &br, alpha: &a)
        if sat < 0.08 {
            return br < 0.55 ? Color.white : Color(white: 0.10)
        }
        if br > 0.62 {
            // Light bubble → deep, saturated same-hue text.
            return Color(
                hue: Double(h),
                saturation: min(1.0, Double(sat) + 0.25),
                brightness: max(0.20, Double(br) - 0.55)
            )
        } else {
            // Dark bubble → soft pastel same-hue text.
            return Color(
                hue: Double(h),
                saturation: max(0.18, Double(sat) - 0.30),
                brightness: min(1.0, Double(br) + 0.55)
            )
        }
    }

    private var shadowTint: Color {
        if let c = customColor { return c.opacity(0.40) }
        switch style {
        // Kit: one soft ~10% black pass under the white cloud.
        case .plain, .music: return Color.black.opacity(0.14)
        case .location: return Color(red: 1.00, green: 0.24, blue: 0.55).opacity(0.40)
        }
    }

    /// Public swatch helper for the editor — returns the parsed color or
    /// a neutral fallback so the swatch grid never renders blank.
    static func swatchColor(_ raw: String) -> Color {
        parseHex(raw) ?? Color.gray.opacity(0.5)
    }

    /// Public gradient helper — returns the same diagonal LinearGradient the
    /// bubble paints itself with so other surfaces (e.g. the story "Reply
    /// to" button) can colour-match a user's What's-on-your-mind choice.
    static func bubbleGradient(colorHex: String, style: WhisperThoughtStyle) -> LinearGradient {
        if let c = parseHex(colorHex) {
            return LinearGradient(
                colors: [c, c.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        switch style {
        case .plain:
            return LinearGradient(
                colors: [Color.white, Color(white: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .location:
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.24, blue: 0.55), Color(red: 1.00, green: 0.45, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .music:
            return LinearGradient(
                colors: [Color(red: 0.48, green: 0.18, blue: 0.97), Color(red: 0.66, green: 0.40, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Foreground color paired with `bubbleGradient(colorHex:style:)` so
    /// label text stays readable on any swatch the user picks.
    static func bubbleTextColor(colorHex: String, style: WhisperThoughtStyle) -> Color {
        if !colorHex.isEmpty, parseHex(colorHex) != nil {
            if let c = complementaryText(forHex: colorHex) { return c }
            return luminanceOfHex(colorHex) < 0.62 ? .white : Color(white: 0.12)
        }
        switch style {
        case .plain, .music: return Color(white: 0.12)
        case .location: return .white
        }
    }

    /// Public luminance helper for the editor's checkmark contrast logic.
    static func luminance(_ raw: String) -> Double {
        luminanceOfHex(raw)
    }

    /// Parses a `#RRGGBB` / `RRGGBB` / `#RRGGBBAA` string into a `Color`.
    /// Returns nil for empty / malformed input so callers can fall back.
    fileprivate static func parseHex(_ raw: String) -> Color? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >>  8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >>  8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private var glyph: String? {
        switch style {
        case .plain:    return nil
        case .location: return "mappin.and.ellipse"
        case .music:    return "music.note"
        }
    }

    private var fontSize: CGFloat { 13 * scale }
    private var hPad: CGFloat { 12 * scale }
    private var vPad: CGFloat { 7 * scale }
    /// Explicit content-derived width, not the host avatar's proposed width.
    /// Identical notes now have identical outlines in Inbox, Home and profiles.
    private var bubbleWidth: CGFloat {
        guard style == .plain else { return 108 * scale }
        guard isCompact, !Self.isEmojiOnly(text) else { return 96 * scale }
        let font = UIFont.systemFont(ofSize: 13 * scale, weight: .semibold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return min(96 * scale, max(44 * scale, ceil(textWidth) + 24 * scale))
    }

    /// Smart-expandable shape: a short note ("gym?") hugs the word in a
    /// compact rounded pill; anything longer expands to the classic 2-line
    /// note, whose footprint is the hard MAX — the bubble never grows past
    /// the base shape.
    private var isCompact: Bool {
        style == .plain && Self.plainFitsOneLine(text, scale: scale)
    }

    /// True when `text` fits a single line inside the plain bubble's max
    /// content width at full font size.
    static func plainFitsOneLine(_ text: String, scale: CGFloat) -> Bool {
        guard !text.contains("\n") else { return false }
        let font = UIFont.systemFont(ofSize: 13 * scale, weight: .semibold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return width <= 72 * scale
    }

    /// Kit 4.0 big-emoji note — a note that's JUST an emoji (1–3 pictographs)
    /// renders it large inside the bubble instead of body-text sized.
    static func isEmojiOnly(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 3 else { return false }
        return t.allSatisfy { ch in
            ch.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
                    || (scalar.properties.isEmoji && scalar.value > 0x238C)
            }
        }
    }

    /// Layout height for a given text/style — shared with
    /// `WhisperAvatarChrome` so avatar overlap stays correct for both the
    /// compact pill and the full note.
    static func measuredHeight(text: String, style: WhisperThoughtStyle, scale: CGFloat) -> CGFloat {
        switch style {
        case .music:    return 50 * scale
        case .location: return 48 * scale
        case .plain:
            if isEmojiOnly(text) { return 46 * scale }
            return plainFitsOneLine(text, scale: scale) ? 34 * scale : 48 * scale
        }
    }

    /// Music bubble is slightly taller so the artist line gets full breathing
    /// room below the title without clipping. Compact notes shrink to hug
    /// a single line.
    private var bubbleHeight: CGFloat { Self.measuredHeight(text: text, style: style, scale: scale) }
    /// Kit proportions: every corner + tail metric derives from the Figma
    /// Union's 41pt-tall body so the cloud keeps its exact shape at any size.
    private var kitUnit: CGFloat { bubbleHeight / 41 }
    /// Keep one softened rectangular character for short and two-line notes.
    private var corner: CGFloat { min(18 * scale, bubbleHeight * 0.42) }
    /// Integrated tail bump — a circle whose centre sits ON the bottom edge
    /// (top half hides behind the body so the outline reads as one union).
    private var bumpSize: CGFloat { 7.86 * kitUnit }
    /// The detached tail dot below-right of the bump (kit: 4pt at (21, 46)).
    private var tailDotSize: CGFloat { 4 * kitUnit }

    var body: some View {
        content
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .frame(width: bubbleWidth)
            .frame(height: bubbleHeight)
            .fixedSize(horizontal: false, vertical: false)
            .background(
                // ONE unified cloud — body + integrated tail bump + detached
                // dot drawn as a single path so the fill flows across the
                // union and the two shadow passes follow the COMPOSITE
                // silhouette (web parity: no seams, no double shadows where
                // the tail meets the body).
                WhisperNotesCloudShape(corner: corner, unit: kitUnit)
                    .fill(bubbleFill)
                    .shadow(color: shadowTint, radius: 5 * kitUnit, x: 0, y: 3 * kitUnit)
                    .shadow(color: Color.black.opacity(0.08), radius: 1 * kitUnit, x: 0, y: 0.5 * kitUnit)
            )
            // Emoji corner sticker — NO disc background, NO outline:
            // the emoji itself sits free, slightly tilted, like the IG Notes
            // "floating emoji" reference. A soft drop shadow gives it depth
            // so it still reads above busy bubble fills.
            //
            // Emoji is ALWAYS pinned to the bubble's top-LEFT corner so the
            // replier-avatar badge can live unambiguously on the top-RIGHT
            // without ever overlapping the emoji. Matches the IG-Notes
            // "floating emoji" reference for the music style and keeps the
            // two corner badges on opposite sides for every other style.
            .overlay(alignment: .topLeading) {
                if !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 22 * scale))
                        .shadow(color: .black.opacity(0.25), radius: 2 * scale, x: 0, y: 1)
                        .rotationEffect(.degrees(14))
                        .offset(x: -10 * scale, y: -12 * scale)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        if style == .plain {
            Text(text)
                .font(.system(size: Self.isEmojiOnly(text) ? 26 * scale : fontSize, weight: .semibold))
                .foregroundStyle(bubbleText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
        } else if style == .music {
            // Music bubble: equalizer + title on the SAME row, artist
            // sits beneath on its own line. The equalizer is pinned to a
            // compact column so its bouncing bars never push the title
            // text rightward or trigger heavier truncation.
            let parts = Self.splitMusicAccent(text: text, accent: accent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6 * scale) {
                    WhisperEqualizerBars(color: bubbleText, bars: 3, size: fontSize * 0.85)
                        .frame(width: fontSize * 0.65, alignment: .center)
                    WhisperMarqueeText(
                        text: parts.title.isEmpty ? "Now playing" : parts.title,
                        font: .system(size: fontSize - 1, weight: .heavy),
                        color: bubbleText
                    )
                    .frame(height: (fontSize - 1) * 1.2)
                }
                if !parts.artist.isEmpty {
                    WhisperMarqueeText(
                        text: parts.artist,
                        font: .system(size: fontSize - 4, weight: .medium),
                        // Kit: artist line is secondary gray (#6F7680), 400 weight.
                        color: customColor != nil
                            ? bubbleText.opacity(0.85)
                            : Color(red: 0.435, green: 0.463, blue: 0.502),
                        speed: 18
                    )
                    .frame(height: (fontSize - 4) * 1.3)
                    // Indent the artist line so it visually aligns with
                    // the title (under the equalizer column).
                    .padding(.leading, (fontSize * 0.65) + (6 * scale))
                }
            }
        } else {
            HStack(spacing: 7 * scale) {
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: fontSize, weight: .heavy))
                        .foregroundStyle(bubbleText)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.isEmpty ? defaultPrimary : text)
                        .font(.system(size: fontSize, weight: .heavy))
                        .foregroundStyle(bubbleText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !accent.isEmpty {
                        Text(accent)
                            .font(.system(size: fontSize - 3, weight: .semibold))
                            .foregroundStyle(bubbleText.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }

    private var defaultPrimary: String {
        switch style {
        case .plain:    return text
        case .location: return "Here now"
        case .music:    return "Now playing"
        }
    }

    private var accessibilityText: String {
        switch style {
        case .plain:    return "Note: \(text)"
        case .location: return "Location: \(accent)"
        case .music:    return "Now playing: \(accent)"
        }
    }
}

/// Instagram-Notes-style sheet for posting / clearing the active thought.
///
/// Has two modes, mirroring Instagram's behavior:
/// - **View** (existing active note): big avatar, the current note text,
///   "Shared with friends · Xh ago", a black "Leave a new note" button,
///   and a red "Delete note" link below.
/// - **Compose** (no active note, or after tapping "Leave a new note"):
///   a compact text field, character counter, preset chips, and a black
///   Share button.
struct WhisperThoughtComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var thoughts = WhisperThoughtService.shared
    @State private var draft: String = ""
    @State private var draftStyle: WhisperThoughtStyle = .plain
    @State private var draftAccent: String = ""
    @State private var draftEmoji: String = ""
    @State private var draftColorHex: String = ""
    @State private var composing: Bool = false
    @State private var showingMusicPicker: Bool = false
    @State private var showingEmojiPicker: Bool = false
    @State private var colorPage: Int = 0
    @State private var resolvingLocation: Bool = false
    @State private var locationError: String?
    @State private var confirmDeleteNote: Bool = false
    @FocusState private var focused: Bool

    /// Curated emoji set — small enough to fit a single pop-over row,
    /// covers the brand-aligned moods (gym, fire, sparkle, love, beach, etc).
    private let emojiOptions: [String] = [
        "🔥", "✨", "💪", "🏆", "🥺", "💜", "🌊", "🌴",
        "☕️", "🍕", "🎧", "🎯", "😎", "🌟", "⚡️", "🤩"
    ]

    /// Curated bubble color palette — 6 swatches per page across 5 pages.
    /// Matches the bright Instagram-Notes vibe: purples, pinks, oranges,
    /// greens, blues, then a neutral row.
    private let colorPages: [[String]] = [
        // Purples / lavenders
        ["#EDE9FE", "#D8B4FE", "#A855F7", "#7C3AED", "#5B21B6", "#2E1065"],
        // Pinks / roses
        ["#FCE7F3", "#F9A8D4", "#F472B6", "#EC4899", "#BE185D", "#831843"],
        // Reds
        ["#FEE2E2", "#FCA5A5", "#F87171", "#EF4444", "#B91C1C", "#7F1D1D"],
        // Oranges
        ["#FFEDD5", "#FDBA74", "#FB923C", "#F97316", "#C2410C", "#7C2D12"],
        // Yellows / golds
        ["#FEF3C7", "#FDE68A", "#FCD34D", "#F59E0B", "#B45309", "#78350F"],
        // Greens
        ["#D1FAE5", "#BBF7D0", "#86EFAC", "#22C55E", "#15803D", "#14532D"],
        // Teals / mint
        ["#CCFBF1", "#5EEAD4", "#14B8A6", "#0D9488", "#115E59", "#042F2E"],
        // Cyans / sky
        ["#CFFAFE", "#A5F3FC", "#22D3EE", "#06B6D4", "#0E7490", "#164E63"],
        // Blues
        ["#DBEAFE", "#BFDBFE", "#60A5FA", "#3B82F6", "#1D4ED8", "#1E3A8A"],
        // Neutrals / mono
        ["#FFFFFF", "#E5E7EB", "#9CA3AF", "#4B5563", "#1F2937", "#000000"]
    ]

    private var displayUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private var charsLeft: Int { thoughts.maxLength - draft.count }
    private var canPost: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= thoughts.maxLength
    }

    private var isViewMode: Bool { thoughts.isActive && !composing }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            if isViewMode {
                viewModeBody
            } else {
                composeModeBody
            }
        }
        .onAppear {
            draft = thoughts.text
            draftStyle = thoughts.style
            draftAccent = thoughts.accent
            draftEmoji = thoughts.emoji
            draftColorHex = thoughts.colorHex
            if !thoughts.isActive {
                composing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
            }
        }
        .sheet(isPresented: $showingMusicPicker) {
            WhisperThoughtMusicSheet { picked in
                draftStyle = .music
                // New format: song title goes in the primary text, artist in
                // accent. Bubble renders title on top + artist below.
                draft = picked.title
                draftAccent = picked.artist
                showingMusicPicker = false
                Haptics.success()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .whisperSheetBorder()
        }
    }

    // MARK: - View mode (matches Instagram note-preview sheet)

    private var viewModeBody: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 4)
            WhisperAvatar(username: displayUsername, size: 90, ring: false)
                .overlay(alignment: .top) {
                    WhisperThoughtBubble(
                        text: thoughts.displayText,
                        scale: 1.0,
                        style: thoughts.style,
                        accent: thoughts.accent,
                        emoji: thoughts.emoji,
                        colorHex: thoughts.colorHex
                    )
                    .offset(y: -22)
                }
                .padding(.top, 28)

            VStack(spacing: 4) {
                Text(thoughts.displayText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("Shared with friends · \(elapsed(thoughts.postedAt))")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    draft = ""
                    withAnimation(.spring(response: 0.32)) { composing = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
                } label: {
                    Text("Leave a new note")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.warning()
                    confirmDeleteNote = true
                } label: {
                    Text("Delete note")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Delete this note?",
                    isPresented: $confirmDeleteNote,
                    titleVisibility: .visible
                ) {
                    Button("Delete note", role: .destructive) {
                        thoughts.clear()
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your note disappears for everyone right away.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Compose mode

    private var composeModeBody: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    if thoughts.isActive {
                        withAnimation(.spring(response: 0.3)) { composing = false }
                    } else {
                        dismiss()
                    }
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Text(thoughts.isActive ? "Edit note" : "New note")
                    .font(.headline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Button {
                    guard canPost else { return }
                    Haptics.success()
                    thoughts.post(draft, style: draftStyle, accent: draftAccent, emoji: draftEmoji, colorHex: draftColorHex)
                    dismiss()
                } label: {
                    Text(thoughts.isActive ? "Update" : "Share")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canPost ? WhisperTheme.surface(colorScheme) : WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(canPost ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canPost)
                .frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 18) {
                    preview
                    inputCard
                    styleToolbar
                    if let locationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.bold))
                            Text(locationError)
                                .font(.caption)
                                .lineLimit(2)
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                    }
                    if showingEmojiPicker { emojiPickerRow }
                    colorEditor
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .presentationContentInteraction(.scrolls)
        }
    }

    private var previewText: String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch draftStyle {
        case .plain:    return "Note..."
        case .location: return "Here now"
        case .music:    return "Now playing"
        }
    }

    // MARK: - Style toolbar (emoji / location / music / plain reset)

    private var styleToolbar: some View {
        HStack(spacing: 10) {
            toolbarChip(
                title: draftEmoji.isEmpty ? "Emoji" : draftEmoji,
                systemImage: draftEmoji.isEmpty ? "face.smiling" : nil,
                tint: Color(red: 1.00, green: 0.78, blue: 0.20),
                active: !draftEmoji.isEmpty
            ) {
                Haptics.tap()
                withAnimation(.spring(response: 0.3)) { showingEmojiPicker.toggle() }
            }
            toolbarChip(
                title: draftStyle == .location ? (draftAccent.isEmpty ? "Locating…" : draftAccent) : "Location",
                systemImage: "mappin.and.ellipse",
                tint: Color(red: 1.00, green: 0.24, blue: 0.55),
                active: draftStyle == .location,
                loading: resolvingLocation
            ) {
                Haptics.tap()
                if draftStyle == .location {
                    draftStyle = .plain
                    draftAccent = ""
                    locationError = nil
                } else {
                    tagLocation()
                }
            }
            toolbarChip(
                title: draftStyle == .music
                    ? (draftAccent.isEmpty && draft.isEmpty ? "Pick song" : "\(draft) \u{2014} \(draftAccent)")
                    : "Music",
                systemImage: "music.note",
                tint: Color(red: 0.48, green: 0.18, blue: 0.97),
                active: draftStyle == .music
            ) {
                Haptics.tap()
                if draftStyle == .music {
                    draftStyle = .plain
                    draftAccent = ""
                } else {
                    showingMusicPicker = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolbarChip(
        title: String,
        systemImage: String?,
        tint: Color,
        active: Bool,
        loading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(active ? .white : tint)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .heavy))
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(active ? Color.white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    active
                        ? AnyShapeStyle(LinearGradient(
                            colors: [tint, tint.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ))
                        : AnyShapeStyle(tint.opacity(0.12))
                )
            )
            .overlay {
                Capsule().strokeBorder(tint.opacity(active ? 0 : 0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// System emoji keyboard hook — instead of a curated row, we pop the
    /// device's native emoji picker so the user can choose any emoji.
    /// `WhisperEmojiKeyboardField` is a `UIViewRepresentable` UITextField
    /// override that returns `"emoji"` from `textInputContextIdentifier`,
    /// which forces the system to default to the emoji keyboard plane.
    private var emojiPickerRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(red: 1.00, green: 0.78, blue: 0.20).opacity(0.18))
                if draftEmoji.isEmpty {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Color(red: 1.00, green: 0.78, blue: 0.20))
                } else {
                    Text(draftEmoji).font(.system(size: 28))
                }
            }
            .frame(width: 46, height: 46)
            .overlay {
                // Invisible TextField captures the single emoji the user
                // picks from the system emoji keyboard. We resign focus
                // immediately on a non-empty value so the keyboard dismisses
                // and the bubble preview updates instantly.
                WhisperEmojiKeyboardField(text: Binding(
                    get: { draftEmoji },
                    set: { new in
                        let stripped = String(new.prefix(2))
                        draftEmoji = stripped
                        if !stripped.isEmpty { Haptics.tap() }
                    }
                ))
                .frame(width: 46, height: 46)
                .opacity(0.02)
                .allowsHitTesting(true)
            }

            Text(draftEmoji.isEmpty ? "Tap to choose an emoji" : "Tap to change")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))

            Spacer()

            if !draftEmoji.isEmpty {
                Button {
                    Haptics.tap()
                    draftEmoji = ""
                } label: {
                    Text("Clear")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func tagLocation() {
        resolvingLocation = true
        locationError = nil
        Task {
            do {
                let ctx = try await EmberLocationService.shared.requestCurrentContext()
                let label: String = {
                    if let city = ctx.city, !city.isEmpty {
                        if let region = ctx.region, !region.isEmpty { return "\(city), \(region)" }
                        return city
                    }
                    if let name = ctx.name, !name.isEmpty { return name }
                    return "Here now"
                }()
                draftStyle = .location
                draftAccent = label
                Haptics.success()
            } catch {
                withAnimation(.whisperSnappy) {
                    locationError = "Couldn't get your location — \(error.localizedDescription)"
                }
                Haptics.warning()
            }
            resolvingLocation = false
        }
    }

    private var preview: some View {
        VStack(spacing: 6) {
            WhisperAvatar(username: displayUsername, size: 76, ring: false)
                .overlay(alignment: .top) {
                    WhisperThoughtBubble(
                        text: previewText,
                        scale: 1.0,
                        style: draftStyle,
                        accent: draftAccent,
                        emoji: draftEmoji,
                        colorHex: draftColorHex
                    )
                    .offset(y: -(36 - 76 * 0.10))
                    // Floating emoji + chip pinned to the top-left of the
                    // bubble (matches the Bubble Editor reference). Tapping
                    // it pops the curated emoji row open.
                    .overlay(alignment: .topLeading) {
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.3)) { showingEmojiPicker.toggle() }
                        } label: {
                            ZStack {
                                Circle().fill(Color.black.opacity(0.78))
                                if draftEmoji.isEmpty {
                                    Image(systemName: "face.smiling")
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(.white)
                                } else {
                                    Text(draftEmoji).font(.system(size: 16))
                                }
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(.white)
                                    .frame(width: 12, height: 12)
                                    .background(Circle().fill(Color(red: 1.00, green: 0.24, blue: 0.45)))
                                    .offset(x: 10, y: -10)
                            }
                            .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .offset(x: -38, y: -(36 - 76 * 0.10) - 6)
                    }
                }
                .padding(.top, 38)
            Text("@\(displayUsername)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.top, 4)
        }
        .padding(.top, 18)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What's on your mind?", text: $draft, axis: .vertical)
                .focused($focused)
                .lineLimit(2...3)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .onChange(of: draft) { _, newValue in
                    if newValue.count > thoughts.maxLength {
                        draft = String(newValue.prefix(thoughts.maxLength))
                    }
                }

            HStack {
                Text("Visible to friends · disappears in 24h")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer()
                Text("\(charsLeft)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(charsLeft < 10 ? .red : WhisperTheme.muted(colorScheme))
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Paginated bubble color editor

    /// Instagram-Notes-style "Bubble Editor": header label + paged swatch
    /// grid + page dots + a small Clear control. Picking a swatch updates
    /// the live preview instantly; tapping the active swatch again clears
    /// the override back to the plain/style default.
    private var colorEditor: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("Bubble color")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer()
                customColorSwatch
                if !draftColorHex.isEmpty {
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.25)) { draftColorHex = "" }
                    } label: {
                        Text("Clear")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            TabView(selection: $colorPage) {
                ForEach(Array(colorPages.enumerated()), id: \.offset) { idx, palette in
                    swatchRow(palette).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 52)
            HStack(spacing: 6) {
                ForEach(0..<colorPages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == colorPage
                              ? WhisperTheme.ink(colorScheme).opacity(0.75)
                              : WhisperTheme.muted(colorScheme).opacity(0.3))
                        .frame(width: i == colorPage ? 16 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: colorPage)
                }
            }
        }
    }

    /// Compact rainbow swatch in the header that opens the system color
    /// picker. Moved out of every page row so the palette rows have room
    /// to breathe and never overlap.
    private var customColorSwatch: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red]),
                        center: .center
                    )
                )
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                .labelsHidden()
                .opacity(0.02)
                .frame(width: 26, height: 26)
        }
        .frame(width: 26, height: 26)
        .overlay {
            Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .accessibilityLabel("Custom color")
    }

    /// System color picker rendered as a swatch — lets users pick any
    /// color outside the curated palette. Bound to `draftColorHex` via
    /// a Color binding that round-trips through hex.
    private var customColorBinding: Binding<Color> {
        Binding(
            get: { WhisperThoughtBubble.swatchColor(draftColorHex.isEmpty ? "#A855F7" : draftColorHex) },
            set: { newColor in
                draftColorHex = newColor.toHex()
                if draftStyle != .plain && draftAccent.isEmpty {
                    draftStyle = .plain
                }
            }
        )
    }

    @ViewBuilder
    private func swatchRow(_ palette: [String]) -> some View {
        // Distribute 6 swatches evenly across the available width so
        // they never overlap on small screens. Each cell expands to fill
        // its share; the swatch inside is capped so it stays circular.
        HStack(spacing: 0) {
            ForEach(palette, id: \.self) { hex in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.25)) {
                        draftColorHex = (draftColorHex.caseInsensitiveCompare(hex) == .orderedSame) ? "" : hex
                        if !draftColorHex.isEmpty && draftStyle != .plain && draftAccent.isEmpty {
                            draftStyle = .plain
                        }
                    }
                } label: {
                    let isOn = draftColorHex.caseInsensitiveCompare(hex) == .orderedSame
                    Circle()
                        .fill(WhisperThoughtBubble.swatchColor(hex))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Circle()
                                .strokeBorder(isOn ? Color.accentColor : WhisperTheme.hairline(colorScheme),
                                              lineWidth: isOn ? 2.5 : 1)
                        }
                        .overlay {
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(
                                        WhisperThoughtBubble.luminance(hex) < 0.6 ? .white : .black
                                    )
                            }
                        }
                        .shadow(color: WhisperThoughtBubble.swatchColor(hex).opacity(isOn ? 0.45 : 0.10),
                                radius: isOn ? 6 : 3, x: 0, y: 2)
                        .scaleEffect(isOn ? 1.08 : 1.0)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func elapsed(_ date: Date?) -> String {
        guard let date else { return "just now" }
        let secs = Date().timeIntervalSince(date)
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(Int(secs / 60))m" }
        if secs < 86_400 { return "\(Int(secs / 3600))h" }
        return "\(Int(secs / 86_400))d"
    }
}

// MARK: - Equalizer bars

/// Lightweight live equalizer used on music thought bubbles in place of the
/// static music.note glyph. Pure SwiftUI — a `TimelineView` ticks the bar
/// heights every animation frame using offset sine waves, so it always
/// reads as "playing" without needing a real audio source.
struct WhisperEqualizerBars: View {
    let color: Color
    var bars: Int = 4
    /// Overall pixel height of the equalizer. Bar width derives from this.
    var size: CGFloat = 13

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: size * 0.16) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: size * 0.22, height: barHeight(i, t: t))
                }
            }
            .frame(height: size, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ i: Int, t: Double) -> CGFloat {
        // Per-bar speed & phase so the bars bounce out of sync — reads as
        // a real audio meter rather than a sine wave march.
        let speeds: [Double] = [3.1, 4.3, 3.7, 4.9, 3.4]
        let phases: [Double] = [0.0, 1.1, 2.3, 0.6, 1.7]
        let s = speeds[i % speeds.count]
        let p = phases[i % phases.count]
        let v = (sin(t * s + p) + 1) / 2 // 0...1
        let minH = size * 0.22
        let maxH = size * 0.95
        return minH + CGFloat(v) * (maxH - minH)
    }
}

// MARK: - Music sheet (shared with stories)

/// Music picker for the "What's on your mind" composer. Uses the same
/// iTunes Search backend as Whisper stories so the song catalog and
/// preview clips stay in sync across both surfaces.
struct WhisperThoughtMusicSheet: View {
    let onPick: (WhisperStoryMusic) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperStoryMusicService.shared
    @State private var nowPlaying = WhisperNowPlayingService.shared
    @State private var player = WhisperStoryMusicPlayer()
    @State private var query: String = ""
    /// Debounce token for search-as-you-type so we don't fire an iTunes
    /// request on every keystroke.
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var resolvingNowPlaying: Bool = false

    private var list: [WhisperStoryMusic] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? service.trending : service.results
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Music")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Button {
                    player.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(WhisperTheme.card(colorScheme)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                TextField("Search songs", text: $query)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .onSubmit { Task { await service.search(query) } }
                    .onChange(of: query) { _, newValue in
                        scheduleSearch(newValue)
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(WhisperTheme.card(colorScheme), in: Capsule())
            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty,
                       nowPlaying.hasNowPlaying {
                        nowPlayingRow
                    }
                    ForEach(list, id: \.id) { song in
                        musicRow(song)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
        }
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
        .task {
            if service.trending.isEmpty {
                await service.loadTrending()
            }
            _ = await nowPlaying.ensureAuthorized()
            nowPlaying.start()
        }
        .onDisappear {
            player.stop()
            searchTask?.cancel()
        }
    }

    /// Debounced live search. Cancels any pending query and schedules a
    /// new one ~280ms after the last keystroke so the picker feels
    /// instant without hammering the iTunes Search endpoint.
    private func scheduleSearch(_ term: String) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            service.results = []
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            if Task.isCancelled { return }
            await service.search(trimmed)
        }
    }

    /// Pinned row that surfaces what the user is actively listening to in
    /// Apple Music. Tap "Use" to attach it to the post — we resolve the
    /// title+artist through iTunes Search to a 30s preview URL so the rest
    /// of the music pipeline (bubble, karaoke, story bg) keeps working.
    @ViewBuilder
    private var nowPlayingRow: some View {
        let title = nowPlaying.nowPlayingTitle ?? ""
        let artist = nowPlaying.nowPlayingArtist ?? ""
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "applelogo")
                    .font(.caption2.weight(.heavy))
                Text("NOW PLAYING")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                Spacer()
                if nowPlaying.isPlaying {
                    WhisperEqualizerBars(
                        color: WhisperTheme.muted(colorScheme),
                        bars: 3,
                        size: 10
                    )
                }
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            HStack(spacing: 12) {
                ZStack {
                    LinearGradient(
                        colors: [Color.pink.opacity(0.85), Color.purple.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task { await pickNowPlaying() }
                } label: {
                    Group {
                        if resolvingNowPlaying {
                            ProgressView()
                                .controlSize(.small)
                                .tint(WhisperTheme.surface(colorScheme))
                        } else {
                            Text("Use")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(resolvingNowPlaying)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    Color.pink.opacity(0.10),
                    Color.purple.opacity(0.10)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.5), Color.purple.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func pickNowPlaying() async {
        resolvingNowPlaying = true
        defer { resolvingNowPlaying = false }
        guard let song = await nowPlaying.resolveCurrentToStoryMusic() else { return }
        player.stop()
        onPick(song)
        dismiss()
    }

    @ViewBuilder
    private func musicRow(_ song: WhisperStoryMusic) -> some View {
        HStack(spacing: 12) {
            ZStack {
                WhisperTheme.card(colorScheme)
                if let art = song.artworkURL, let url = URL(string: art) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.clear
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                player.toggle(song)
            } label: {
                Image(systemName: player.nowPlayingID == song.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .buttonStyle(.plain)
            Button {
                player.stop()
                onPick(song)
                dismiss()
            } label: {
                Text("Use")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

// MARK: - Lyrics sheet (tap a music bubble)

/// Free, no-key lyrics endpoint. Returns `{ "lyrics": "..." }` for any
/// `"<artist>/<title>"` pair iTunes Search would resolve.
nonisolated struct WhisperLyricsResponse: Decodable, Sendable {
    let lyrics: String?
    let error: String?
}

/// Sheet that opens when a music thought bubble is tapped. Shows the
/// styled bubble at the top, fetches lyrics from lyrics.ovh, and exposes
/// a reply composer at the bottom so viewers can message the poster back
/// about the song — same shape as Instagram's note-reply UX.
struct WhisperThoughtLyricsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let accent: String
    let emoji: String
    let colorHex: String
    /// Visual treatment of the original thought — drives which reply UI we
    /// render. Music shows the karaoke lyrics centerpiece; location shows a
    /// pinned location card; plain shows a clean centered bubble. Default
    /// stays `.music` to preserve behaviour for any legacy call sites.
    var style: WhisperThoughtStyle = .music
    /// Display name of the poster ("@username"); shown above the reply field.
    let posterUsername: String
    /// User ID of the poster — used to resolve the avatar image URL and to
    /// route the reply DM to the correct conversation. Optional so legacy
    /// call sites (owner mode, previews) still compile.
    var posterUserID: String? = nil
    /// ISO-8601 timestamp of when the thought was posted. When present, the
    /// header renders "@username · 13h" Instagram-style; otherwise just the
    /// username.
    var postedAtISO: String? = nil
    /// When true, the sheet renders the owner-mode layout: gradient header,
    /// single-line cycling lyric, and an "Edit" pill instead of the reply
    /// composer. Defaults to false (viewer mode).
    var isOwner: Bool = false
    /// Called when the user taps Send on a non-empty reply. Receives the
    /// raw reply string. Parent dismisses the sheet on its own.
    var onReply: ((String) -> Void)? = nil
    /// Called when the owner taps "Edit" in owner mode.
    var onEdit: (() -> Void)? = nil

    @State private var lyrics: String? = nil
    @State private var lyricLines: [String] = []
    @State private var activeLineIndex: Int = 0
    @State private var musicPlayer = WhisperStoryMusicPlayer()
    @State private var previewURL: String? = nil
    /// Apple Music catalog song ID resolved from the iTunes/Apple Music
    /// search. When present and the viewer is subscribed, playback is the
    /// full track via `ApplicationMusicPlayer` instead of the 30s preview.
    @State private var resolvedCatalogID: String? = nil
    /// 0...1, drives the bold/highlighted portion of the active lyric line
    /// so it expands left-to-right as if synced to the vocal.
    @State private var lineProgress: Double = 0
    @State private var lyricTimer: Task<Void, Never>? = nil
    @State private var loadError: String? = nil
    @State private var isLoading: Bool = true
    @State private var artworkURL: String? = nil
    @State private var reply: String = ""
    @FocusState private var replyFocused: Bool

    /// Approximate seconds spent on each cycling lyric line when we can't
    /// sync to actual playback. With audio playing we drive the cycle off
    /// `musicPlayer.currentTime` instead so pause / resume / seek behave
    /// as expected.
    private let secondsPerLine: Double = 3.4
    /// Tracks whether the karaoke line cycle is being driven by the audio
    /// playhead. Flipped on the first `currentTime` tick we see; while true
    /// we suppress the fallback timer so the two don't fight.
    @State private var playheadDriven: Bool = false

    private var parts: (title: String, artist: String) {
        WhisperThoughtBubble.splitMusicAccent(text: text, accent: accent)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 14)
            avatarAndBubble
            if style == .music {
                Spacer(minLength: 12)
                musicCenterpiece
            }
            Spacer(minLength: 0)
            if isOwner {
                ownerActionBar
            } else {
                replyBar
            }
        }
        .background(
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
        )
        .task {
            // Reset the karaoke state every time the sheet appears so the
            // first lyric line is always line 0 — keeps the on-screen lyric
            // in lock-step with the freshly-started audio (Instagram parity).
            activeLineIndex = 0
            lineProgress = 0
            playheadDriven = false
            if style == .music {
                await load()
            } else {
                isLoading = false
            }
        }
        .onChange(of: musicPlayer.isListenAlong) { _, isListenAlong in
            // Only pull lyrics once we have a real playhead to lock them
            // to — preview clips would render the karaoke out of sync.
            guard style == .music, isListenAlong, lyricLines.isEmpty else { return }
            let p = parts
            Task { await fetchLyrics(title: p.title, artist: p.artist) }
        }
        .onChange(of: musicPlayer.currentTime) { _, t in
            guard style == .music else { return }
            syncLyricsTo(time: t)
        }
        .onDisappear {
            lyricTimer?.cancel()
            musicPlayer.stop()
        }
    }

    // MARK: Centerpieces

    /// Centered "avatar + bubble" pair, mirroring the Instagram-Notes reply
    /// layout exactly: small profile picture on the left, the user's styled
    /// thought bubble floating to its right. The same composition is used
    /// for plain / location / music — only the bubble differs.
    private var avatarAndBubble: some View {
        HStack(alignment: .center, spacing: 12) {
            WhisperAvatar(
                username: posterUsername,
                size: 52,
                ring: false
            )
            WhisperThoughtBubble(
                text: text,
                scale: 1.1,
                style: style,
                accent: accent,
                emoji: emoji,
                colorHex: colorHex
            )
        }
        .padding(.horizontal, 24)
    }

    /// Music-only centerpiece below the avatar/bubble row. When the viewer
    /// is streaming the full track via Apple Music we render the same
    /// karaoke lyric sweep as before (but smaller, IG-Notes-sized). When
    /// they're not, we show a quiet "Listen on Apple Music" CTA so the
    /// space below the bubble still feels intentional.
    @ViewBuilder
    private var musicCenterpiece: some View {
        if musicPlayer.isListenAlong, !lyricLines.isEmpty {
            karaokeLine
                .padding(.horizontal, 32)
        } else {
            appleMusicCTA
                .padding(.horizontal, 32)
        }
    }

    /// Compact single-line karaoke sweep — the active lyric, with the
    /// already-sung portion bold and the trailing portion dimmed. Matches
    /// the "Medicina de amor, quiero de ti" treatment in the reference.
    private var karaokeLine: some View {
        let line = lyricLines.indices.contains(activeLineIndex)
            ? lyricLines[activeLineIndex]
            : ""
        let splitIdx = highlightSplitIndex(for: line, progress: lineProgress)
        let highlighted = String(line.prefix(splitIdx))
        let trailing = String(line.dropFirst(splitIdx))
        return (
            Text(highlighted)
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(WhisperTheme.ink(colorScheme))
            +
            Text(trailing)
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(WhisperTheme.ink(colorScheme).opacity(0.30))
        )
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .id(activeLineIndex)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.45), value: activeLineIndex)
    }

    /// Pill button rendered when the viewer isn't streaming full tracks —
    /// deep-links into Apple Music at the exact song. Works for everyone,
    /// no sign-in required (falls back to the web page on devices without
    /// the Music app installed).
    @ViewBuilder
    private var appleMusicCTA: some View {
        if let id = resolvedCatalogID, let url = appleMusicURL(for: id) {
            Button {
                Haptics.tap()
                UIApplication.shared.open(url)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 12, weight: .heavy))
                    Text("Listen on Apple Music")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(0.2)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .heavy))
                }
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(WhisperTheme.ink(colorScheme))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Plain / location hero layouts (legacy — unused in unified layout)

    /// Centerpiece for a plain text thought — large quoted message in the
    /// poster's chosen color, with the emoji floating above as a corner badge.
    private var plainHero: some View {
        VStack(spacing: 24) {
            if !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 56))
                    .rotationEffect(.degrees(-8))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.30), radius: 12, y: 4)
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.white.opacity(0.10))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .padding(.horizontal, 28)
        }
    }

    /// Centerpiece for a location thought — pin glyph + city name + the
    /// user's note as a quoted subtitle. Mirrors the IG-Notes "travelling
    /// somewhere" reply layout.
    private var locationHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    .frame(width: 96, height: 96)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.30), radius: 6, y: 3)
            }
            if !accent.isEmpty {
                Text(accent)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.30), radius: 10, y: 4)
                    .padding(.horizontal, 24)
            }
            if !text.isEmpty && text != "Now here" {
                Text("\u{201C}\(text)\u{201D}")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 36))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: Header

    /// Centered minimal header: drag indicator handled by the parent sheet,
    /// so we only render "@username · 13h" centered with a close affordance
    /// on the left. Matches the IG-Notes reply sheet exactly.
    private var header: some View {
        let ink = WhisperTheme.ink(colorScheme)
        return HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(ink.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(ink.opacity(0.08)))
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 6) {
                Text("@\(posterUsername)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                if let stamp = relativeStamp {
                    Text("·")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.45))
                    Text(stamp)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.55))
                }
            }
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// "13h" / "3d" style timestamp from the persisted ISO string. Returns
    /// nil when no timestamp is available (owner mode, legacy call sites).
    private var relativeStamp: String? {
        guard let iso = postedAtISO, !iso.isEmpty else { return nil }
        let label = WhisperPost.relativeTime(from: iso)
        return label.isEmpty ? nil : label
    }

    // MARK: Bubble hero

    private var bubbleHero: some View {
        WhisperThoughtBubble(
            text: text,
            scale: 1.4,
            style: .music,
            accent: accent,
            emoji: emoji,
            colorHex: colorHex
        )
    }

    // MARK: Compact song strip (full-screen karaoke header)

    /// One-line song header pinned beneath the close/username row —
    /// artwork thumbnail, title + artist on one line, play/pause toggle
    /// on the right. Keeps the karaoke lyric the dominant element.
    private var compactSongStrip: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.12))
                if let s = artworkURL, let url = URL(string: s) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.clear
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(parts.title.isEmpty ? "Now playing" : parts.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if musicPlayer.isListenAlong {
                        listenAlongBadge
                    }
                }
                Text(parts.artist.isEmpty ? "—" : parts.artist)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            openInAppleMusicButton
            if previewURL != nil {
                Button(action: togglePlayback) {
                    Image(systemName: musicPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// Small Apple-logo chip — retained for any legacy call sites; the
    /// unified layout uses `appleMusicCTA` below the bubble instead.
    @ViewBuilder
    private var openInAppleMusicButton: some View {
        if let id = resolvedCatalogID, let url = appleMusicURL(for: id) {
            Button {
                UIApplication.shared.open(url)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 10, weight: .heavy))
                    Text("Open")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.3)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.16)))
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.32), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open in Apple Music")
        }
    }

    /// Builds the universal Apple Music deep link. `music.apple.com/song/{id}`
    /// resolves without a storefront prefix and is handled by the Music app
    /// when installed (falls back to the web on devices without it).
    private func appleMusicURL(for catalogID: String) -> URL? {
        URL(string: "https://music.apple.com/song/\(catalogID)")
    }

    /// Tiny chip surfaced in the song strip when full-track Apple Music
    /// playback is active — tells the viewer they're hearing the whole
    /// song, not the 30s preview.
    private var listenAlongBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "applelogo")
                .font(.system(size: 9, weight: .heavy))
            Text("LISTEN-ALONG")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(.white.opacity(0.18))
        )
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.32), lineWidth: 0.5)
        }
    }

    // MARK: Song card (artwork + title + artist) — legacy, retained for owner mode use elsewhere

    @ViewBuilder
    private var songCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.12))
                if let s = artworkURL, let url = URL(string: s) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.clear
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(parts.title.isEmpty ? "Now playing" : parts.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(parts.artist.isEmpty ? "—" : parts.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            Spacer()
            if previewURL != nil {
                Button(action: togglePlayback) {
                    Image(systemName: musicPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Preview hero (non Apple-Music viewers)

    /// Centerpiece shown when the viewer isn't streaming the full song via
    /// Apple Music. We hide the karaoke (preview clips don't start at 0s,
    /// so the lyric sweep would be wrong) and instead lean into a clean
    /// album-art hero with a clear "Open in Apple Music" CTA — same
    /// pattern Instagram uses for non-subscriber notes.
    private var previewHero: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.10))
                if let s = artworkURL, let url = URL(string: s) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color.clear
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(.rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)

            VStack(spacing: 6) {
                Text(parts.title.isEmpty ? "Now playing" : parts.title)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.30), radius: 8, y: 3)
                Text(parts.artist.isEmpty ? "—" : parts.artist)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }

            if let id = resolvedCatalogID, let url = appleMusicURL(for: id) {
                Button {
                    Haptics.tap()
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Listen on Apple Music")
                            .font(.system(size: 14, weight: .heavy))
                            .tracking(0.2)
                    }
                    .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.14))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(.white))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Text("Synced lyrics play in Apple Music.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.2)
                .padding(.top, 2)
        }
    }

    // MARK: Lyrics body

    @ViewBuilder
    private var lyricsBody: some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Finding lyrics…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if !lyricLines.isEmpty {
            cyclingLyricView
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
                Text(loadError ?? "Lyrics aren't available for this track.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 30)
        }
    }

    /// IG-style "karaoke" lyric ticker: one line at a time, with the
    /// active portion bold-white and the remainder dimmed. The highlight
    /// sweeps left-to-right over `secondsPerLine`, then the next line
    /// fades up into place. Without LRC data this is approximate sync —
    /// but it matches the feel of the reference shot.
    ///
    /// Renders as a full-screen stadium-style centerpiece: large bold
    /// active line, dimmed previous + next lines floating above and
    /// below to give the karaoke flow context.
    private var cyclingLyricView: some View {
        let line = lyricLines.indices.contains(activeLineIndex)
            ? lyricLines[activeLineIndex]
            : ""
        let splitIdx = highlightSplitIndex(for: line, progress: lineProgress)
        let highlighted = String(line.prefix(splitIdx))
        let trailing = String(line.dropFirst(splitIdx))
        let prev = lyricLines.indices.contains(activeLineIndex - 1)
            ? lyricLines[activeLineIndex - 1] : nil
        let next = lyricLines.indices.contains(activeLineIndex + 1)
            ? lyricLines[activeLineIndex + 1] : nil
        return VStack(spacing: 22) {
            if !isOwner, let prev {
                Text(prev)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.22))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .id("prev-\(activeLineIndex)")
                    .transition(.opacity)
            }
            // Active line — large stadium-style karaoke text.
            (
                Text(highlighted)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(.white)
                +
                Text(trailing)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(.white.opacity(0.30))
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .id(activeLineIndex)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal:   .opacity.combined(with: .move(edge: .top))
            ))
            if !isOwner, let next {
                Text(next)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.32))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .id("next-\(activeLineIndex)")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: activeLineIndex)
    }

    // MARK: - Owner action bar (Edit / Delete)

    /// Bottom bar rendered in owner mode — same chrome as the viewer
    /// reply bar, but with a wide "Edit note" pill and a muted "Delete
    /// note" link beneath it.
    private var ownerActionBar: some View {
        let ink = WhisperTheme.ink(colorScheme)
        return VStack(spacing: 8) {
            Button {
                Haptics.tap()
                musicPlayer.stop()
                onEdit?()
                dismiss()
            } label: {
                Text("Edit note")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(ink))
            }
            .buttonStyle(.plain)

            Button {
                Haptics.warning()
                WhisperThoughtService.shared.clear()
                musicPlayer.stop()
                dismiss()
            } label: {
                Text("Delete note")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.65))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// Returns how many characters of `line` should render highlighted
    /// at the given progress (0...1). Rounds to the nearest word boundary
    /// so partial words don't flash bold mid-letter.
    private func highlightSplitIndex(for line: String, progress: Double) -> Int {
        guard !line.isEmpty else { return 0 }
        let clamped = max(0, min(1, progress))
        let target = Int(Double(line.count) * clamped)
        if target >= line.count { return line.count }
        // Snap forward to next space so we cut on a word boundary.
        let chars = Array(line)
        var idx = target
        while idx < chars.count && chars[idx] != " " { idx += 1 }
        return min(idx, line.count)
    }

    // MARK: Reply bar

    /// Quick-reaction emoji set surfaced inline in the message bar — taps
    /// fire a one-tap reply with just that emoji, matching IG's note-reply
    /// behaviour. Hidden once the user starts typing so the field can grow.
    private let quickReactions: [String] = ["\u{1F60D}", "\u{1F44A}", "\u{1F614}"]

    private var replyBar: some View {
        let ink = WhisperTheme.ink(colorScheme)
        let pillFill = colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
        let hasText = !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $reply,
                    prompt: Text("Message \(posterUsername)")
                        .foregroundStyle(ink.opacity(0.55))
                )
                .foregroundStyle(ink)
                .tint(ink)
                .focused($replyFocused)
                .submitLabel(.send)
                .onSubmit(send)
                if !hasText {
                    HStack(spacing: 14) {
                        ForEach(quickReactions, id: \.self) { emoji in
                            Button {
                                sendQuick(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 20))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("React with \(emoji)")
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(pillFill))

            if hasText {
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(ink))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    sendQuick("\u{2764}\u{FE0F}")
                } label: {
                    Image(systemName: "heart")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ink)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send a heart")
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: hasText)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func send() {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.success()
        onReply?(trimmed)
        reply = ""
        replyFocused = false
        dismiss()
    }

    /// One-tap reaction send — used by the inline emojis and the heart.
    /// Skips the empty-string guard since each emoji is itself the reply.
    private func sendQuick(_ emoji: String) {
        Haptics.success()
        onReply?(emoji)
        dismiss()
    }

    // MARK: Data

    private func load() async {
        // Lyrics are now fetched lazily in `.onChange(of: isListenAlong)`
        // — we only want them when the viewer is actually listening on
        // Apple Music, so 30s-preview viewers never see misaligned lines.
        isLoading = false
        let p = parts
        await fetchArtwork(title: p.title, artist: p.artist)
    }

    private func fetchArtwork(title: String, artist: String) async {
        guard !title.isEmpty else { return }
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "media", value: "music"),
        ]
        guard let url = comps.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(WhisperStoryMusicResponse.self, from: data)
            if let first = decoded.results.first {
                if let art = first.artworkUrl100 {
                    artworkURL = art.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                }
                // Stash the 30-second preview URL and auto-play so the sheet
                // doubles as a mini-player like Instagram Notes.
                if let preview = first.previewUrl {
                    previewURL = preview
                    resolvedCatalogID = "\(first.trackId)"
                    // iTunes `trackId` doubles as the Apple Music catalog
                    // ID, so we can attempt full-track listen-along when
                    // the viewer has an Apple Music subscription.
                    let song = WhisperStoryMusic(
                        id: "thought-\(title)-\(artist)",
                        title: title,
                        artist: artist,
                        artworkURL: artworkURL,
                        previewURL: preview,
                        startSeconds: 0,
                        catalogID: "\(first.trackId)"
                    )
                    // Stop any in-flight player and start fresh from t=0 so
                    // the lyrics karaoke sync begins at line 0 alongside the
                    // first audio sample — IG-style "tap to play from start".
                    await MainActor.run {
                        musicPlayer.stop()
                        musicPlayer.play(song)
                    }
                }
            }
        } catch {
            // Silent — lyrics card still renders with the music-note glyph.
        }
    }

    /// Toggles preview playback on the artwork card.
    private func togglePlayback() {
        guard let preview = previewURL else { return }
        let song = WhisperStoryMusic(
            id: "thought-\(parts.title)-\(parts.artist)",
            title: parts.title,
            artist: parts.artist,
            artworkURL: artworkURL,
            previewURL: preview,
            catalogID: resolvedCatalogID
        )
        musicPlayer.toggle(song)
        Haptics.tap()
    }

    private func fetchLyrics(title: String, artist: String) async {
        defer { isLoading = false }
        guard !title.isEmpty, !artist.isEmpty else {
            loadError = "Tap the bubble after picking a song to view lyrics."
            return
        }
        let a = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? artist
        let t = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://api.lyrics.ovh/v1/\(a)/\(t)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(WhisperLyricsResponse.self, from: data)
            if let raw = decoded.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                lyrics = raw
                lyricLines = raw
                    .split(whereSeparator: { $0.isNewline })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                startLyricCycle()
            } else {
                loadError = decoded.error ?? "No lyrics found for this track."
            }
        } catch {
            loadError = "Couldn't load lyrics. Try again later."
        }
    }

    /// Pulls the active lyric line + progress from the audio playhead so
    /// the karaoke sweep stays locked to playback. Without LRC timestamps
    /// we approximate by dividing the elapsed time into fixed-length
    /// slices, but pause / resume / scrubbing all behave naturally because
    /// the source of truth is `AVPlayer.currentTime`.
    private func syncLyricsTo(time t: Double) {
        guard !lyricLines.isEmpty, t.isFinite, t >= 0 else { return }
        playheadDriven = true
        lyricTimer?.cancel()
        let perLine = secondsPerLine
        let totalLines = lyricLines.count
        let rawIdx = Int(t / perLine)
        let idx = totalLines > 0 ? (rawIdx % totalLines) : 0
        let frac = perLine > 0 ? (t.truncatingRemainder(dividingBy: perLine)) / perLine : 0
        if idx != activeLineIndex {
            withAnimation(.easeInOut(duration: 0.35)) {
                activeLineIndex = idx
                lineProgress = max(0, min(1, frac))
            }
        } else {
            withAnimation(.linear(duration: 0.1)) {
                lineProgress = max(0, min(1, frac))
            }
        }
    }

    /// Drives the karaoke-style line cycle. Each line holds for
    /// `secondsPerLine` while `lineProgress` ramps 0 → 1; on the last
    /// line we loop back to the top so the sheet feels alive even after
    /// the song would have ended. Only used as a fallback when no audio
    /// playback is available (e.g. preview URL missing) — once the
    /// playhead sync kicks in, `playheadDriven` keeps this loop disabled.
    private func startLyricCycle() {
        lyricTimer?.cancel()
        activeLineIndex = 0
        lineProgress = 0
        guard !lyricLines.isEmpty else { return }
        lyricTimer = Task { @MainActor in
            while !Task.isCancelled {
                if playheadDriven { return }
                let steps = 30
                let stepDelay = secondsPerLine / Double(steps)
                for s in 1...steps {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(Int(stepDelay * 1000)))
                    if Task.isCancelled { return }
                    withAnimation(.linear(duration: stepDelay)) {
                        lineProgress = Double(s) / Double(steps)
                    }
                }
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    activeLineIndex = (activeLineIndex + 1) % lyricLines.count
                    lineProgress = 0
                }
            }
        }
    }
}
