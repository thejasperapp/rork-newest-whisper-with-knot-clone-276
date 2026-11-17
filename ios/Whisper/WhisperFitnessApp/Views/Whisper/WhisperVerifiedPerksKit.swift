import Foundation
import SwiftUI
import PhotosUI
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// -- Custom accent color + banner image (verified-only). Stored on
// -- whisper_profiles so they travel with the existing profile row and
// -- there's no extra fetch.
// alter table public.whisper_profiles
//   add column if not exists accent_color text,
//   add column if not exists banner_url   text;
//
// -- Featured links: up to 5 pinned external links shown as a horizontal
// -- card row under the bio. Verified accounts only — the UI enforces the
// -- gate; RLS just makes sure you can only write your own rows.
// create table if not exists public.whisper_featured_links (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   title text not null,
//   url text not null,
//   emoji text,
//   position int not null default 0,
//   created_at timestamptz not null default now()
// );
// create index if not exists whisper_featured_links_user_idx
//   on public.whisper_featured_links(user_id, position asc);
// alter table public.whisper_featured_links enable row level security;
// drop policy if exists "wfl read all" on public.whisper_featured_links;
// create policy "wfl read all" on public.whisper_featured_links for select using (true);
// drop policy if exists "wfl write own" on public.whisper_featured_links;
// create policy "wfl write own" on public.whisper_featured_links
//   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
//
// -- Pinned posts: up to 3 posts pinned to the top of the threads tab.
// -- Composite PK so re-pinning the same post is a no-op.
// create table if not exists public.whisper_pinned_posts (
//   user_id uuid not null references auth.users(id) on delete cascade,
//   post_id uuid not null,
//   position int not null default 0,
//   pinned_at timestamptz not null default now(),
//   primary key (user_id, post_id)
// );
// create index if not exists whisper_pinned_posts_user_idx
//   on public.whisper_pinned_posts(user_id, position asc);
// alter table public.whisper_pinned_posts enable row level security;
// drop policy if exists "wpp read all" on public.whisper_pinned_posts;
// create policy "wpp read all" on public.whisper_pinned_posts for select using (true);
// drop policy if exists "wpp write own" on public.whisper_pinned_posts;
// create policy "wpp write own" on public.whisper_pinned_posts
//   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
//
// notify pgrst, 'reload schema';

// MARK: - Models

nonisolated struct WhisperFeaturedLink: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let title: String
    let url: String
    let emoji: String?
    let position: Int?
    let created_at: String?
}

nonisolated struct WhisperFeaturedLinkInsert: Codable, Sendable {
    let id: String
    let user_id: String
    let title: String
    let url: String
    let emoji: String?
    let position: Int
}

nonisolated struct WhisperFeaturedLinkUpdate: Codable, Sendable {
    let title: String
    let url: String
    let emoji: String?
    let position: Int
}

nonisolated struct WhisperPinnedPostRow: Codable, Sendable, Identifiable, Hashable {
    let user_id: String
    let post_id: String
    let position: Int?
    nonisolated var id: String { user_id + ":" + post_id }
}

nonisolated struct WhisperPinnedPostInsert: Codable, Sendable {
    let user_id: String
    let post_id: String
    let position: Int
}

nonisolated struct WhisperAccentColorPatch: Codable, Sendable {
    let accent_color: String?
    let updated_at: String
}

nonisolated struct WhisperBannerURLPatch: Encodable, Sendable {
    let banner_url: String?
    let updated_at: String

    private enum CodingKeys: String, CodingKey { case banner_url, banner_offset_y, updated_at }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        // Explicit null is required to remove a cover; encodeIfPresent omits it.
        try values.encode(banner_url, forKey: .banner_url)
        try values.encode(0.0, forKey: .banner_offset_y)
        try values.encode(updated_at, forKey: .updated_at)
    }
}

nonisolated struct WhisperBannerOffsetPatch: Codable, Sendable {
    let banner_offset_y: Double
    let updated_at: String
}

// SQL (run once):
// alter table public.whisper_profiles
//   add column if not exists banner_offset_y double precision not null default 0;

// MARK: - Service

/// Verified-only perks: featured links, pinned posts, custom accent color.
/// All three surfaces share a single service so we round-trip once per
/// profile load and the rest of the app reads from in-memory caches.
@MainActor
@Observable
final class WhisperVerifiedPerksService {
    static let shared = WhisperVerifiedPerksService()

    private let client = SupabaseService.shared.client

    /// Featured links keyed by owner user_id, in display order.
    var linksByUser: [String: [WhisperFeaturedLink]] = [:]
    /// Pinned post IDs keyed by owner user_id, in display order. Max 3.
    var pinnedByUser: [String: [String]] = [:]
    /// Custom accent color hex (e.g. "#FF3366") keyed by owner user_id.
    var accentByUser: [String: String] = [:]
    /// Custom profile banner image URL keyed by owner user_id.
    var bannerByUser: [String: String] = [:]
    /// Vertical reposition offset (in points) for each user's banner image.
    /// Stored on `whisper_profiles.banner_offset_y` so the drag-positioned
    /// crop persists across devices and is seen by other viewers too.
    var bannerOffsetByUser: [String: Double] = [:]
    /// Ignore a read begun before a newer cover mutation.
    private var bannerRevisions: [String: UUID] = [:]

    var lastError: String?

    /// Hard cap matching the IG model — keep the row visually scannable.
    static let maxFeaturedLinks: Int = 5
    static let maxPinnedPosts: Int = 3

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    /// Returns the live auth UID from the active Supabase session — what RLS
    /// actually checks against. The cached `AccountStorage.currentUserID` can
    /// drift out of sync (Apple Hide-My-Email rotation, password reset, magic
    /// link, etc.), and Storage policies that compare the upload folder against
    /// `auth.uid()` will silently reject writes when that happens.
    private func resolvedUID() async -> String? {
        if let session = try? await client.auth.session {
            let live = session.user.id.uuidString.lowercased()
            if WhisperIdentityService.isValidSupabaseUID(live) {
                if AccountStorage.currentUserID.lowercased() != live {
                    AccountStorage.currentUserID = live
                }
                return live
            }
        }
        let cached = AccountStorage.currentUserID
        return WhisperIdentityService.isValidSupabaseUID(cached) ? cached.lowercased() : nil
    }

    private init() {}

    // MARK: - Reads

    func links(forUserID userID: String) -> [WhisperFeaturedLink] {
        linksByUser[userID] ?? []
    }

    func pinnedPostIDs(forUserID userID: String) -> [String] {
        pinnedByUser[userID] ?? []
    }

    func accentColor(forUserID userID: String) -> Color? {
        guard let hex = accentByUser[userID], let c = Self.color(fromHex: hex) else { return nil }
        return c
    }

    func bannerURL(forUserID userID: String) -> URL? {
        guard let raw = bannerByUser[userID.lowercased()], !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// Vertical reposition offset for the user's banner image (points).
    /// Positive values pan the image down; negative pan it up. Defaults to 0
    /// (image centred).
    func bannerOffsetY(forUserID userID: String) -> Double {
        bannerOffsetByUser[userID.lowercased()] ?? 0
    }

    func refresh(forUserID userID: String) async {
        guard isRemote else { return }
        async let links: Void = refreshLinks(forUserID: userID)
        async let pins: Void = refreshPinned(forUserID: userID)
        async let cover: Void = refreshAccentAndBanner(forUserID: userID)
        _ = await (links, pins, cover)
    }

    func refreshLinks(forUserID userID: String) async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        do {
            let rows: [WhisperFeaturedLink] = try await client
                .from("whisper_featured_links")
                .select()
                .eq("user_id", value: userID)
                .order("position", ascending: true)
                .order("created_at", ascending: true)
                .limit(Self.maxFeaturedLinks)
                .execute()
                .value
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            linksByUser[userID] = rows
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            lastError = error.localizedDescription
        }
    }

    func refreshPinned(forUserID userID: String) async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        do {
            let rows: [WhisperPinnedPostRow] = try await client
                .from("whisper_pinned_posts")
                .select()
                .eq("user_id", value: userID)
                .order("position", ascending: true)
                .limit(Self.maxPinnedPosts)
                .execute()
                .value
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            pinnedByUser[userID] = rows.map { $0.post_id }
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            lastError = error.localizedDescription
        }
    }

    private nonisolated struct AccentBannerRow: Codable, Sendable {
        let accent_color: String?
        let banner_url: String?
        let banner_offset_y: Double?
    }

    /// Back-compat shim — older call sites just want the accent refreshed.
    func refreshAccent(forUserID userID: String) async {
        await refreshAccentAndBanner(forUserID: userID)
    }

    func refreshAccentAndBanner(forUserID userID: String) async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        let revision = bannerRevisions[userID.lowercased()]
        do {
            let rows: [AccentBannerRow] = try await client
                .from("whisper_profiles")
                .select("accent_color,banner_url,banner_offset_y")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            guard generation == AccountStorage.generation, !Task.isCancelled,
                  revision == bannerRevisions[userID.lowercased()] else { return }
            let row = rows.first
            if let hex = row?.accent_color, !hex.isEmpty {
                accentByUser[userID] = hex
            } else {
                accentByUser.removeValue(forKey: userID)
            }
            if let url = row?.banner_url, !url.isEmpty {
                bannerByUser[userID.lowercased()] = url
            } else {
                bannerByUser.removeValue(forKey: userID.lowercased())
            }
            if let offset = row?.banner_offset_y {
                bannerOffsetByUser[userID.lowercased()] = offset
            } else {
                bannerOffsetByUser.removeValue(forKey: userID.lowercased())
            }
        } catch {
            // Column may not exist yet — surfaced only on save.
        }
    }

    // MARK: - Featured links

    @discardableResult
    func addLink(title: String, url: String, emoji: String?) async -> WhisperFeaturedLink? {
        guard isRemote else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedURL.isEmpty else { return nil }
        let normalizedURL = Self.normalizedURL(trimmedURL)
        let existing = linksByUser[currentUID] ?? []
        guard existing.count < Self.maxFeaturedLinks else {
            lastError = "You can pin up to \(Self.maxFeaturedLinks) links."
            WhisperErrorService.shared.report("You can pin up to \(Self.maxFeaturedLinks) links.")
            return nil
        }
        let payload = WhisperFeaturedLinkInsert(
            id: UUID().uuidString,
            user_id: currentUID,
            title: trimmedTitle,
            url: normalizedURL,
            emoji: (emoji?.isEmpty ?? true) ? nil : emoji,
            position: existing.count
        )
        do {
            let inserted: [WhisperFeaturedLink] = try await client
                .from("whisper_featured_links")
                .insert(payload)
                .select()
                .execute()
                .value
            if let row = inserted.first {
                linksByUser[currentUID, default: []].append(row)
                Analytics.record("featured_link_added", [:])
                return row
            }
        } catch {
            lastError = "Couldn't save link. \(error.localizedDescription)"
            WhisperErrorService.shared.report("Couldn't save link. Try again.")
        }
        return nil
    }

    func updateLink(_ link: WhisperFeaturedLink, title: String, url: String, emoji: String?) async {
        guard isRemote else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedURL.isEmpty else { return }
        let normalizedURL = Self.normalizedURL(trimmedURL)
        let payload = WhisperFeaturedLinkUpdate(
            title: trimmedTitle,
            url: normalizedURL,
            emoji: (emoji?.isEmpty ?? true) ? nil : emoji,
            position: link.position ?? 0
        )
        do {
            try await client.from("whisper_featured_links")
                .update(payload)
                .eq("id", value: link.id)
                .eq("user_id", value: currentUID)
                .execute()
            await refreshLinks(forUserID: currentUID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteLink(_ id: String) async {
        guard isRemote else { return }
        do {
            try await client.from("whisper_featured_links")
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: currentUID)
                .execute()
            linksByUser[currentUID]?.removeAll { $0.id == id }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Pinned posts

    var isAtPinnedLimit: Bool {
        (pinnedByUser[currentUID]?.count ?? 0) >= Self.maxPinnedPosts
    }

    func isPinned(postID: String) -> Bool {
        (pinnedByUser[currentUID] ?? []).contains(postID)
    }

    func pin(postID: String) async {
        guard isRemote else { return }
        var current = pinnedByUser[currentUID] ?? []
        guard !current.contains(postID) else { return }
        guard current.count < Self.maxPinnedPosts else {
            lastError = "You can pin up to \(Self.maxPinnedPosts) posts."
            WhisperErrorService.shared.report("You can pin up to \(Self.maxPinnedPosts) posts.")
            return
        }
        let payload = WhisperPinnedPostInsert(
            user_id: currentUID,
            post_id: postID,
            position: current.count
        )
        do {
            try await client.from("whisper_pinned_posts")
                .insert(payload)
                .execute()
            current.append(postID)
            pinnedByUser[currentUID] = current
            Analytics.record("post_pinned", [:])
        } catch {
            lastError = "Couldn't pin. \(error.localizedDescription)"
            WhisperErrorService.shared.report("Couldn't pin post. Try again.")
        }
    }

    func unpin(postID: String) async {
        guard isRemote else { return }
        do {
            try await client.from("whisper_pinned_posts")
                .delete()
                .eq("user_id", value: currentUID)
                .eq("post_id", value: postID)
                .execute()
            pinnedByUser[currentUID]?.removeAll { $0 == postID }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Accent color

    func setAccentColor(_ hex: String?) async {
        guard isRemote else { return }
        let iso = ISO8601DateFormatter().string(from: Date())
        let payload = WhisperAccentColorPatch(accent_color: hex, updated_at: iso)
        do {
            try await client.from("whisper_profiles")
                .update(payload)
                .eq("user_id", value: currentUID)
                .execute()
            if let hex, !hex.isEmpty {
                accentByUser[currentUID] = hex
            } else {
                accentByUser.removeValue(forKey: currentUID)
            }
        } catch {
            lastError = "Couldn't save accent color. \(error.localizedDescription)"
            WhisperErrorService.shared.report("Couldn't save accent color. Try again.")
        }
    }

    // MARK: - Banner image

    /// Uploads a uniquely named JPEG into the existing owner-folder `banners`
    /// bucket, then commits its URL only for the account that began the upload.
    @discardableResult
    func uploadBanner(jpegData: Data) async -> String? {
        guard isRemote else {
            lastError = "Sign in to save a cover photo."
            return nil
        }
        let generation = AccountStorage.generation
        let uid = currentUID
        guard let session = try? await client.auth.session,
              session.user.id.uuidString.lowercased() == uid.lowercased(),
              coverOperationIsCurrent(uid: uid, generation: generation) else {
            if generation == AccountStorage.generation {
                lastError = "Couldn't upload cover photo. Please sign in again."
                logCoverFailure(stage: "session")
            }
            return nil
        }
        lastError = nil
        bannerRevisions[uid.lowercased()] = UUID()
        let path = "\(uid.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        do {
            _ = try await client.storage
                .from("banners")
                .upload(
                    path: path,
                    file: jpegData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        // Every path is new. Do not require Storage UPDATE permission.
                        upsert: false
                    )
                )
            guard coverOperationIsCurrent(uid: uid, generation: generation) else { return nil }
            let publicURL = try client.storage.from("banners").getPublicURL(path: path)
            let urlString = publicURL.absoluteString
            guard await commitBannerURL(urlString, uid: uid, generation: generation) else { return nil }
            return urlString
        } catch {
            guard coverOperationIsCurrent(uid: uid, generation: generation) else { return nil }
            logCoverFailure(stage: "storage-upload", error: error)
            let detail = error.localizedDescription
            lastError = "Cover upload failed: \(detail)"
            WhisperErrorService.shared.report("Cover upload failed. See the cover editor for details.")
            return nil
        }
    }

    @discardableResult
    func setBannerURL(_ url: String?) async -> Bool {
        guard isRemote else { return false }
        return await commitBannerURL(url, uid: currentUID, generation: AccountStorage.generation)
    }

    private func coverOperationIsCurrent(uid: String, generation: UUID) -> Bool {
        generation == AccountStorage.generation && uid.lowercased() == currentUID.lowercased() && !Task.isCancelled
    }

    private nonisolated struct SavedCover: Decodable {
        let user_id: String
        let banner_url: String?
        let banner_offset_y: Double?
    }

    /// Log only stage/type/code: never account IDs, URLs, photos or credentials.
    private func logCoverFailure(stage: String, error: Error? = nil) {
        let type = error.map { String(describing: Swift.type(of: $0)) } ?? "UnconfirmedWrite"
        let code = (error as? PostgrestError)?.code ?? "none"
        print("[WhisperCover] stage=\(stage) result=failed type=\(type) code=\(code)")
    }

    private func commitBannerURL(_ url: String?, uid: String, generation: UUID) async -> Bool {
        guard coverOperationIsCurrent(uid: uid, generation: generation) else { return false }
        bannerRevisions[uid.lowercased()] = UUID()
        let iso = ISO8601DateFormatter().string(from: Date())
        let payload = WhisperBannerURLPatch(banner_url: url, updated_at: iso)
        do {
            let saved: [SavedCover] = try await client.from("whisper_profiles")
                .update(payload)
                .eq("user_id", value: uid)
                .select("user_id,banner_url,banner_offset_y")
                .execute().value
            guard coverOperationIsCurrent(uid: uid, generation: generation) else { return false }
            guard saved.contains(where: {
                $0.user_id.lowercased() == uid.lowercased() && $0.banner_url == url && $0.banner_offset_y == 0
            }) else {
                logCoverFailure(stage: "profile-confirmation")
                lastError = "Cover wasn't saved: your profile didn't confirm the change. Please try again."
                return false
            }
            bannerOffsetByUser[uid.lowercased()] = 0
            if let url, !url.isEmpty {
                bannerByUser[uid.lowercased()] = url
            } else {
                bannerByUser.removeValue(forKey: uid.lowercased())
            }
            lastError = nil
            return true
        } catch {
            guard coverOperationIsCurrent(uid: uid, generation: generation) else { return false }
            logCoverFailure(stage: "profile-save", error: error)
            lastError = "Cover profile save failed: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func clearBanner() async -> Bool {
        await setBannerURL(nil)
    }

    /// Persists the user-chosen vertical reposition offset (in points) for
    /// the banner image. Publish the new crop only after a successful save.
    @discardableResult
    func setBannerOffset(_ value: Double) async -> Bool {
        guard isRemote, value.isFinite else { return false }
        let uid = currentUID
        let generation = AccountStorage.generation
        let clamped = max(-300, min(300, value))
        bannerRevisions[uid.lowercased()] = UUID()
        let iso = ISO8601DateFormatter().string(from: Date())
        let payload = WhisperBannerOffsetPatch(banner_offset_y: clamped, updated_at: iso)
        do {
            let saved: [SavedCover] = try await client.from("whisper_profiles")
                .update(payload)
                .eq("user_id", value: uid)
                .select("user_id,banner_url,banner_offset_y")
                .execute().value
            guard coverOperationIsCurrent(uid: uid, generation: generation) else { return false }
            guard saved.contains(where: { $0.user_id.lowercased() == uid.lowercased() && $0.banner_offset_y == clamped }) else {
                logCoverFailure(stage: "position-confirmation")
                lastError = "Cover position wasn't saved: your profile didn't confirm the change."
                return false
            }
            bannerOffsetByUser[uid.lowercased()] = clamped
            lastError = nil
            return true
        } catch {
            guard coverOperationIsCurrent(uid: uid, generation: generation) else { return false }
            logCoverFailure(stage: "position-save", error: error)
            lastError = "Couldn't save cover position. \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Utilities

    /// Drops the leading `#` and parses 6- or 8-char hex into a SwiftUI Color.
    static func color(fromHex raw: String) -> Color? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let val = UInt32(s, radix: 16) else { return nil }
        let r: Double
        let g: Double
        let b: Double
        let a: Double
        if s.count == 8 {
            a = Double((val >> 24) & 0xFF) / 255.0
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8)  & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
        } else {
            a = 1.0
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8)  & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private static func normalizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }
}

// MARK: - Featured Links row

/// Horizontal row of up to 5 pinned external links shown right under the
/// bio on a verified profile. Owner sees a `+` tile that opens the editor.
struct WhisperFeaturedLinksRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    let userID: String
    let username: String
    let isMe: Bool

    @State private var perks = WhisperVerifiedPerksService.shared
    @State private var presentEditor: Bool = false

    private var isVerified: Bool {
        WhisperVerifiedPerks.isVerified(username: username)
    }

    private var links: [WhisperFeaturedLink] {
        perks.links(forUserID: userID)
    }

    var body: some View {
        Group {
            if isVerified && (!links.isEmpty || isMe) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(links) { link in
                            linkChip(link)
                        }
                        if isMe && links.count < WhisperVerifiedPerksService.maxFeaturedLinks {
                            addChip
                        }
                    }
                    .padding(.vertical, 4)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
        }
        .task {
            await perks.refreshLinks(forUserID: userID)
        }
        .sheet(isPresented: $presentEditor) {
            WhisperFeaturedLinksEditorSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func linkChip(_ link: WhisperFeaturedLink) -> some View {
        let social = WhisperSocialBrand.detect(from: link.url)
        return Button {
            Haptics.tap()
            if let url = URL(string: link.url) { openURL(url) }
        } label: {
            HStack(spacing: 8) {
                if let social {
                    social.iconView(size: 18)
                } else if let emoji = link.emoji, !emoji.isEmpty {
                    Text(emoji).font(.subheadline)
                } else {
                    Image(systemName: "link")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text(displayHost(link.url))
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .frame(maxWidth: 200, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isMe {
                Button {
                    presentEditor = true
                } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) {
                    Task { await perks.deleteLink(link.id) }
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private var addChip: some View {
        Button {
            Haptics.tap()
            presentEditor = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                Text(links.isEmpty ? "Add featured link" : "Add")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        WhisperTheme.hairline(colorScheme),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func displayHost(_ raw: String) -> String {
        guard let url = URL(string: raw), let host = url.host else { return raw }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - Featured Links editor

struct WhisperFeaturedLinksEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var perks = WhisperVerifiedPerksService.shared

    @State private var newTitle: String = ""
    @State private var newURL: String = ""
    @State private var newEmoji: String = ""
    @State private var saving: Bool = false

    private var me: String { AccountStorage.currentUserID }
    private var links: [WhisperFeaturedLink] { perks.links(forUserID: me) }
    private var canAdd: Bool { links.count < WhisperVerifiedPerksService.maxFeaturedLinks }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if canAdd { newRow } else { fullNote }
                        if !links.isEmpty {
                            Text("Your links")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            VStack(spacing: 0) {
                                ForEach(Array(links.enumerated()), id: \.element.id) { _, link in
                                    existingRow(link)
                                    Divider().background(WhisperTheme.hairline(colorScheme))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Featured links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task { await perks.refreshLinks(forUserID: me) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pin up to \(WhisperVerifiedPerksService.maxFeaturedLinks) external links")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("YouTube, IG, Linktree, your shop — whatever you want your profile to send people to.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.horizontal, 16)
    }

    private var newRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("🎬", text: $newEmoji)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(width: 44, height: 44)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                TextField("Title (e.g. YouTube)", text: $newTitle)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
            }
            TextField("https://...", text: $newURL)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
            Button {
                Haptics.tap()
                Task {
                    saving = true
                    if await perks.addLink(title: newTitle, url: newURL, emoji: newEmoji.isEmpty ? nil : newEmoji) != nil {
                        newTitle = ""; newURL = ""; newEmoji = ""
                    }
                    saving = false
                }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().controlSize(.small).tint(WhisperTheme.surface(colorScheme)) }
                    Text(saving ? "Saving…" : "Add link")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || saving)
        }
        .padding(.horizontal, 16)
    }

    private var fullNote: some View {
        Text("You've hit the \(WhisperVerifiedPerksService.maxFeaturedLinks)-link cap. Delete one below to add another.")
            .font(.caption)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 16)
    }

    private func existingRow(_ link: WhisperFeaturedLink) -> some View {
        let social = WhisperSocialBrand.detect(from: link.url)
        return HStack(spacing: 12) {
            if let social {
                social.iconView(size: 22)
            } else if let emoji = link.emoji, !emoji.isEmpty {
                Text(emoji).font(.title3)
            } else {
                Image(systemName: "link")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(link.url)
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                Haptics.warning()
                Task { await perks.deleteLink(link.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Accent color picker

/// Curated palette + reset for the verified accent-color perk. Lives in
/// Edit Profile (visible to verified users only).
struct WhisperAccentColorPicker: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var perks = WhisperVerifiedPerksService.shared

    private let swatches: [(name: String, hex: String)] = [
        ("Sunset",   "#FF5C5C"),
        ("Coral",    "#FF8A5B"),
        ("Saffron",  "#F2B544"),
        ("Lime",     "#7ED957"),
        ("Mint",     "#3CC9A7"),
        ("Sky",      "#3CA5FF"),
        ("Indigo",   "#5B5BFF"),
        ("Violet",   "#A26BFF"),
        ("Hot Pink", "#FF4FAE"),
        ("Slate",    "#7C8794")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile accent")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    resetTile
                    ForEach(swatches, id: \.hex) { s in
                        tile(name: s.name, hex: s.hex)
                    }
                }
                .padding(.vertical, 4)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            Text("Tints your header gradient + role pill glow across Whisper.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 16)
        }
        .padding(.top, 4)
    }

    private var currentHex: String? {
        perks.accentByUser[AccountStorage.currentUserID]
    }

    private var resetTile: some View {
        Button {
            Haptics.tap()
            Task { await perks.setAccentColor(nil) }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: "slash.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                if currentHex == nil {
                    Circle()
                        .strokeBorder(WhisperTheme.ink(colorScheme), lineWidth: 2)
                        .frame(width: 50, height: 50)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func tile(name: String, hex: String) -> some View {
        let isSelected = currentHex?.lowercased() == hex.lowercased()
        return Button {
            Haptics.tap()
            Task { await perks.setAccentColor(hex) }
        } label: {
            ZStack {
                Circle()
                    .fill(WhisperVerifiedPerksService.color(fromHex: hex) ?? Color.accentColor)
                    .frame(width: 44, height: 44)
                if isSelected {
                    Circle()
                        .strokeBorder(WhisperTheme.ink(colorScheme), lineWidth: 2)
                        .frame(width: 50, height: 50)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel(name)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile banner

/// Cover photo rendered at the top of a verified user's profile — a
/// rounded-corner rectangle card (not full bleed) so it reads as a framed
/// banner above the identity header.
struct WhisperProfileBannerView: View {
    @Environment(\.colorScheme) private var colorScheme

    let userID: String
    let username: String

    @State private var perks = WhisperVerifiedPerksService.shared

    private var isVerified: Bool {
        WhisperVerifiedPerks.isVerified(username: username)
    }

    private var bannerURL: URL? { perks.bannerURL(forUserID: userID) }
    private var accent: Color? { perks.accentColor(forUserID: userID) }
    private var imageOffsetY: CGFloat { CGFloat(perks.bannerOffsetY(forUserID: userID)) }

    /// Banner card height — a framed rectangle, not a full-bleed hero.
    private let bannerHeight: CGFloat = 148

    var body: some View {
        Group {
            if isVerified, let url = bannerURL {
                WhisperTheme.card(colorScheme)
                    .frame(height: bannerHeight)
                    .overlay {
                        WhisperCachedAsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .offset(y: imageOffsetY)
                                    .allowsHitTesting(false)
                            } else {
                                WhisperTheme.card(colorScheme)
                            }
                        }
                    }
                    .overlay {
                        // Soft scrim so anything overlaid stays legible
                        // against bright banners.
                        LinearGradient(
                            colors: [
                                Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06),
                                Color.black.opacity(0.0),
                                Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var accentGradient: some View {
        let tint = accent ?? WhisperTheme.ink(colorScheme)
        LinearGradient(
            colors: [
                tint.opacity(0.55),
                tint.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Banner editor row (lives inside Edit Profile)

/// Cover-photo controls using the existing profile banner storage. Saves
/// separately from the edit-profile draft, with visible failures.
struct WhisperProfileBannerEditor: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var perks = WhisperVerifiedPerksService.shared
    @State private var pickedItem: PhotosPickerItem?
    @Binding var uploading: Bool
    @State private var generation = AccountStorage.generation
    @State private var errorMessage: String?
    @State private var pendingJPEG: Data?
    @State private var coverSaved = false
    private var valid: Bool { generation == AccountStorage.generation && !Task.isCancelled }
    /// Live drag delta while the user is repositioning the banner image.
    /// Committed onto `perks.setBannerOffset` when the gesture ends.
    @State private var dragOffset: CGFloat = 0

    private var me: String { AccountStorage.currentUserID }
    private var currentURL: URL? { perks.bannerURL(forUserID: me) }
    private var savedOffset: CGFloat { CGFloat(perks.bannerOffsetY(forUserID: me)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cover photo")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 16)

            preview
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 8) {
                        if uploading {
                            ProgressView().controlSize(.small).tint(WhisperTheme.surface(colorScheme))
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.bold))
                        }
                        Text(uploading ? "Saving\u{2026}" : (currentURL == nil ? "Choose cover" : "Replace cover"))
                            .font(.subheadline.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 12))
                }
                .disabled(uploading)

                if currentURL != nil {
                    Button(role: .destructive) {
                        Haptics.warning()
                        uploading = true
                        errorMessage = nil
                        pendingJPEG = nil
                        coverSaved = false
                        Task {
                            defer { uploading = false }
                            guard valid else { return }
                            let ok = await perks.clearBanner()
                            guard valid else { return }
                            if !ok { errorMessage = perks.lastError ?? "Couldn't remove cover photo. Try again." }
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.red)
                            .frame(width: 48, height: 44)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove cover photo")
                    .disabled(uploading)
                }
            }
            .padding(.horizontal, 16)

            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    if let pendingJPEG {
                        Button("Retry cover save") {
                            guard valid, !uploading else { return }
                            uploading = true
                            Task {
                                defer { uploading = false }
                                await saveSelectedCover(pendingJPEG)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(uploading)
                    }
                }
                .padding(.horizontal, 16)
            } else if coverSaved {
                Label("Cover saved", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 16)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if currentURL != nil {
                Text("Drag the preview to reposition.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 16)
            }

            Text("Saves separately from your profile edits. Shown behind your portrait and profile panel. Recommended size 1500\u{00D7}500.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 4)
        .task {
            guard valid else { return }
            uploading = true
            defer { uploading = false }
            await perks.refreshAccentAndBanner(forUserID: me)
        }
        .onChange(of: pickedItem) { _, newValue in
            guard let newValue else { return }
            handlePicked(newValue)
        }
    }

    private var preview: some View {
        Color(.secondarySystemBackground)
            .frame(height: 196)
            .overlay {
                if let url = currentURL {
                    WhisperProfileCoverImage(url: url, offset: Double(savedOffset + dragOffset))
                } else {
                    placeholder.allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 12))
            .gesture(
                currentURL == nil || uploading ? nil :
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let proposed = value.translation.height
                        // Clamp so the user can't drag the image entirely
                        // out of frame on either side.
                        let limit: CGFloat = 300
                        let combined = max(-limit, min(limit, savedOffset + proposed)) - savedOffset
                        dragOffset = combined
                    }
                    .onEnded { _ in
                        let committed = Double(savedOffset + dragOffset)
                        dragOffset = 0
                        Haptics.tap()
                        savePosition(committed)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(currentURL == nil ? "Cover photo preview, no photo" : "Cover photo position")
            .accessibilityValue("\(Int(savedOffset))")
            .accessibilityAdjustableAction { direction in
                guard currentURL != nil else { return }
                switch direction {
                case .increment: savePosition(Double(savedOffset + 15))
                case .decrement: savePosition(Double(savedOffset - 15))
                @unknown default: break
                }
            }
    }

    @ViewBuilder
    private var placeholder: some View {
        WhisperTheme.card(colorScheme)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.title3.weight(.bold))
                    Text("No cover photo yet")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
    }

    private func savePosition(_ value: Double) {
        guard valid, !uploading else { return }
        uploading = true
        errorMessage = nil
        Task {
            defer { uploading = false }
            guard valid else { return }
            let ok = await perks.setBannerOffset(value)
            guard valid else { return }
            if !ok { errorMessage = perks.lastError ?? "Couldn't save cover position. Try again." }
        }
    }

    private func handlePicked(_ item: PhotosPickerItem) {
        guard valid, !uploading else { return }
        print("[WhisperCover] stage=photo-selection result=started")
        errorMessage = nil
        pendingJPEG = nil
        coverSaved = false
        uploading = true
        Task {
            defer {
                uploading = false
                pickedItem = nil
            }
            do {
                guard let raw = try await item.loadTransferable(type: Data.self), valid else {
                    if valid { errorMessage = "Couldn't read selected photo." }
                    return
                }
                guard let jpeg = Self.normalizedJPEG(from: raw), valid else {
                    if valid { errorMessage = "Couldn't read that photo. Try another image." }
                    return
                }
                await saveSelectedCover(jpeg)
            } catch {
                if valid { errorMessage = error.localizedDescription }
            }
        }
    }

    private func saveSelectedCover(_ jpeg: Data) async {
        guard valid else { return }
        errorMessage = nil
        coverSaved = false
        pendingJPEG = jpeg
        let result = await perks.uploadBanner(jpegData: jpeg)
        guard valid else { return }
        if result == nil {
            errorMessage = perks.lastError ?? "Cover couldn't be saved. Please try again."
        } else {
            pendingJPEG = nil
            coverSaved = true
            print("[WhisperCover] stage=profile-confirmation result=saved")
        }
    }

    /// Downscale + re-encode to bound banner payload size.
    private static func normalizedJPEG(from data: Data, maxDimension: CGFloat = 1600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
