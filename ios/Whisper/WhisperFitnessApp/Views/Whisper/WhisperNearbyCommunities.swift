import SwiftUI
import MapKit
import CoreLocation

// MARK: - Service

/// Geo-aware community suggestions — Whisper looks at what's physically
/// around the user and unlocks local hubs: a college nearby opens the
/// campus pack (Whisper Law, Whisper Med, Whisper Business, Whisper Code),
/// and each gym becomes its own crew community named after the real place
/// (e.g. "Relentless Fitness"). Suggestions are plain `WhisperCommunity`
/// values, so joining, posting (#hashtag matching), and the detail feed all
/// work through the existing machinery with zero backend.
///
/// Location is one-shot (EmberLocationService). Discoveries are ADDITIVE
/// and PER-ACCOUNT: every college and gym this account has been near stays
/// on its list (deduped, newest finds first) — a new scan ADDS hubs, it
/// never replaces earlier finds, and one account's scan can't touch
/// another's list. Scans are considered fresh for 24h; the unlocked hubs
/// themselves never expire.
@MainActor
@Observable
final class WhisperNearbyCommunitiesService {
    static let shared = WhisperNearbyCommunitiesService()

    enum Phase: Equatable {
        case idle
        /// Location permission hasn't been granted — show the enable card.
        case needsPermission
        case loading
        case ready
        /// Located fine but nothing recognizable around (or search failed).
        case unavailable
    }

    var phase: Phase = .idle
    var suggestions: [WhisperCommunity] = []

    private var inflight: Bool = false
    private let cacheKey = "whisper_nearby_communities_v1"
    private let cacheTTL: TimeInterval = 86_400

    private init() {}

    /// Loads cache instantly, then decides whether the UI should show the
    /// permission card or live results.
    func bootstrap() {
        if let cached = loadCache(), !cached.isEmpty {
            suggestions = cached
            phase = .ready
            // Stale scan (>24h) — quietly rescan and MERGE so new places
            // around the user ADD ON to their unlocked hubs.
            if !cacheIsFresh, EmberLocationService.shared.isAuthorized {
                Task { await refresh(force: true) }
            }
            return
        }
        guard phase == .idle else { return }
        phase = EmberLocationService.shared.isAuthorized ? .idle : .needsPermission
        if EmberLocationService.shared.isAuthorized {
            Task { await refresh(force: false) }
        }
    }

    /// Runs the live lookup. `force: true` is the explicit user tap — it may
    /// trigger the system permission prompt. Every scan MERGES its finds
    /// into the account's accumulated list — discovery only ever ADDS.
    func refresh(force: Bool) async {
        guard !inflight else { return }
        if !force, cacheIsFresh, let cached = loadCache(), !cached.isEmpty {
            suggestions = cached
            phase = .ready
            return
        }
        if !force && !EmberLocationService.shared.isAuthorized {
            phase = suggestions.isEmpty ? .needsPermission : .ready
            return
        }
        inflight = true
        if suggestions.isEmpty { phase = .loading }
        defer { inflight = false }

        let context: EmberLocationContext
        do {
            context = try await EmberLocationService.shared.requestCurrentContext()
        } catch {
            if suggestions.isEmpty {
                phase = EmberLocationService.shared.isAuthorized ? .unavailable : .needsPermission
            } else {
                phase = .ready
            }
            return
        }

        let center = CLLocationCoordinate2D(latitude: context.latitude, longitude: context.longitude)
        let here = CLLocation(latitude: context.latitude, longitude: context.longitude)

        async let universities = search(query: "university", poi: [.university], center: center)
        async let gyms = search(query: "gym", poi: [.fitnessCenter], center: center)
        let uniItems = await universities
        let gymItems = await gyms

        // Up to 3 nearest distinct colleges + 3 nearest distinct gyms PER
        // SCAN — each merges into the saved list instead of replacing it.
        var found: [GeoCacheEntry] = []

        var seenCampuses = Set<String>()
        let sortedCampuses = uniItems
            .compactMap { item -> (String, CLLocationDistance, String?)? in
                guard let name = item.name, !name.isEmpty else { return nil }
                let loc = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                return (name, here.distance(from: loc), Self.address(of: item))
            }
            .sorted { $0.1 < $1.1 }
        for (name, dist, address) in sortedCampuses {
            let key = name.lowercased()
            guard !seenCampuses.contains(key) else { continue }
            seenCampuses.insert(key)
            found.append(GeoCacheEntry(
                id: "geo-campus-\(Self.slug(of: name))",
                name: name,
                origin: Self.distanceLabel(dist),
                kind: "campus",
                address: address
            ))
            if seenCampuses.count >= 3 { break }
        }

        var seenNames = Set<String>()
        let sortedGyms = gymItems
            .compactMap { item -> (String, CLLocationDistance, String?)? in
                guard let name = item.name, !name.isEmpty else { return nil }
                let loc = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                return (name, here.distance(from: loc), Self.address(of: item))
            }
            .sorted { $0.1 < $1.1 }
        for (name, dist, address) in sortedGyms {
            let key = name.lowercased()
            guard !seenNames.contains(key) else { continue }
            seenNames.insert(key)
            found.append(GeoCacheEntry(
                id: "geo-gym-\(Self.slug(of: name))",
                name: name,
                origin: Self.distanceLabel(dist),
                kind: "gym",
                address: address
            ))
            if seenNames.count >= 3 { break }
        }

        let merged = Self.merge(existing: loadEntries(), found: found)
        saveEntries(merged)
        let built = Self.build(from: merged)
        suggestions = built
        phase = built.isEmpty ? .unavailable : .ready
    }

    private func search(
        query: String,
        poi: [MKPointOfInterestCategory],
        center: CLLocationCoordinate2D
    ) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: poi)
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 24_000,
            longitudinalMeters: 24_000
        )
        let response = try? await MKLocalSearch(request: request).start()
        return response?.mapItems ?? []
    }

    /// Short human street address ("123 Main St, Cambridge") for the info
    /// sheet — built from placemark parts so we never store coordinates.
    private static func address(of item: MKMapItem) -> String? {
        let p = item.placemark
        var parts: [String] = []
        if let street = p.thoroughfare {
            if let number = p.subThoroughfare {
                parts.append("\(number) \(street)")
            } else {
                parts.append(street)
            }
        }
        if let city = p.locality {
            parts.append(city)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: - Community builders (shared naming with web for caption matching)

    static func campusPack(near campusName: String, address: String? = nil) -> [WhisperCommunity] {
        let origin = "Near \(campusName)"
        return [
            WhisperCommunity(
                id: "geo-law", name: "Whisper Law",
                tagline: "Case briefs, cold calls, bar prep — the law students' common room.",
                symbol: "building.columns.fill",
                keywords: ["whisperlaw", "law school", "law student", "bar exam", "case brief", "1l ", "2l ", "3l "],
                gradient: [Color(red: 0.16, green: 0.22, blue: 0.38), Color(red: 0.72, green: 0.58, blue: 0.30)],
                specialReact: "⚖️", origin: origin, originAddress: address
            ),
            WhisperCommunity(
                id: "geo-med", name: "Whisper Med",
                tagline: "Rotations, match day, and surviving anatomy — future docs unite.",
                symbol: "stethoscope",
                keywords: ["whispermed", "med school", "med student", "rotations", "match day", "anatomy", "usmle"],
                gradient: [Color(red: 0.16, green: 0.55, blue: 0.56), Color(red: 0.45, green: 0.84, blue: 0.78)],
                specialReact: "🩺", origin: origin, originAddress: address
            ),
            WhisperCommunity(
                id: "geo-business", name: "Whisper Business",
                tagline: "Pitches, internships, first ventures — the business school floor.",
                symbol: "briefcase.fill",
                keywords: ["whisperbusiness", "b-school", "mba", "internship", "pitch deck", "startup"],
                gradient: [Color(red: 0.23, green: 0.25, blue: 0.30), Color(red: 0.85, green: 0.68, blue: 0.38)],
                specialReact: "💼", origin: origin, originAddress: address
            ),
            WhisperCommunity(
                id: "geo-code", name: "Whisper Code",
                tagline: "Problem sets, hackathons, ship days — engineers and CS kids.",
                symbol: "chevron.left.forwardslash.chevron.right",
                keywords: ["whispercode", "hackathon", "problem set", "leetcode", "comp sci", "engineering"],
                gradient: [Color(red: 0.32, green: 0.24, blue: 0.60), Color(red: 0.62, green: 0.52, blue: 0.96)],
                specialReact: "💻", origin: origin, originAddress: address
            )
        ]
    }

    static func gymCommunity(named name: String, distanceMeters: CLLocationDistance?, address: String? = nil) -> WhisperCommunity {
        let slug = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
        let origin: String
        if let d = distanceMeters {
            let km = d / 1000
            origin = km < 1
                ? "\(Int(d.rounded())) m away"
                : String(format: "%.1f km away", km)
        } else {
            origin = "Near you"
        }
        return WhisperCommunity(
            id: "geo-gym-\(slug)", name: name,
            tagline: "The \(name) crew — sessions, PRs, and meetups at the gym.",
            symbol: "dumbbell.fill",
            keywords: [name.lowercased(), slug],
            gradient: [Color(red: 0.93, green: 0.42, blue: 0.22), Color(red: 1.00, green: 0.70, blue: 0.40)],
            specialReact: "💪", origin: origin, originAddress: address
        )
    }

    /// One community per nearby college — named after the real campus so
    /// every discovered school ACCUMULATES as its own hub (same ids as web).
    static func campusCommunity(named name: String, distanceMeters: CLLocationDistance?, address: String? = nil) -> WhisperCommunity {
        let origin = distanceMeters.map { Self.distanceLabel($0) } ?? "Near you"
        return WhisperCommunity(
            id: "geo-campus-\(Self.slug(of: name))", name: name,
            tagline: "The \(name) yard — classes, clubs, and campus life.",
            symbol: "graduationcap.fill",
            keywords: [name.lowercased(), Self.slug(of: name)],
            gradient: [Color(red: 0.24, green: 0.35, blue: 0.66), Color(red: 0.56, green: 0.72, blue: 0.96)],
            specialReact: "🎓", origin: origin, originAddress: address
        )
    }

    static func slug(of name: String) -> String {
        name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }

    static func distanceLabel(_ distance: CLLocationDistance) -> String {
        let km = distance / 1000
        return km < 1
            ? "\(Int(distance.rounded())) m away"
            : String(format: "%.1f km away", km)
    }

    // MARK: - Cache

    private nonisolated struct GeoCacheEntry: Codable {
        let id: String
        let name: String
        let origin: String
        /// "campus" | "gym" (legacy caches may carry "law"/"med"/"business"/
        /// "code" pack markers — migrated to a campus entry on load).
        let kind: String
        /// Street address of the real place (optional — old caches decode nil).
        var address: String? = nil
    }
    private nonisolated struct GeoCache: Codable {
        let stamp: Date
        let entries: [GeoCacheEntry]
    }

    /// True while the last scan is under 24h old. Content itself never
    /// expires — this only gates automatic re-scans.
    private var cacheIsFresh: Bool {
        guard let json = AccountStorage.string(forKey: cacheKey),
              let data = json.data(using: .utf8),
              let cache = try? JSONDecoder().decode(GeoCache.self, from: data) else { return false }
        return Date().timeIntervalSince(cache.stamp) < cacheTTL
    }

    /// Decoded entries with legacy pack markers migrated to campus entries.
    private func loadEntries() -> [GeoCacheEntry] {
        guard let json = AccountStorage.string(forKey: cacheKey),
              let data = json.data(using: .utf8),
              let cache = try? JSONDecoder().decode(GeoCache.self, from: data) else { return [] }
        var out: [GeoCacheEntry] = []
        for entry in cache.entries {
            switch entry.kind {
            case "campus", "gym":
                out.append(entry)
            case "law", "med", "business", "code":
                // Legacy pack marker — recover the campus it came from.
                let name = entry.origin.hasPrefix("Near ")
                    ? String(entry.origin.dropFirst(5))
                    : ""
                guard !name.isEmpty else { continue }
                out.append(GeoCacheEntry(
                    id: "geo-campus-\(Self.slug(of: name))",
                    name: name,
                    origin: "Near you",
                    kind: "campus",
                    address: entry.address
                ))
            default:
                break
            }
        }
        // merge() dedupes repeated legacy pack markers into one campus.
        return Self.merge(existing: [], found: out)
    }

    private func saveEntries(_ entries: [GeoCacheEntry]) {
        let cache = GeoCache(stamp: Date(), entries: entries)
        if let data = try? JSONEncoder().encode(cache),
           let json = String(data: data, encoding: .utf8) {
            AccountStorage.set(json, forKey: cacheKey)
        }
    }

    /// Add-or-refresh merge — fresh finds first (with updated distance
    /// labels), earlier finds kept, nothing ever removed. Capped at 6
    /// campuses + 8 gyms.
    private static func merge(existing: [GeoCacheEntry], found: [GeoCacheEntry]) -> [GeoCacheEntry] {
        var seen = Set<String>()
        var merged: [GeoCacheEntry] = []
        for entry in found + existing {
            guard !entry.name.isEmpty else { continue }
            let key = "\(entry.kind):\(Self.slug(of: entry.name))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(entry)
        }
        let campuses = merged.filter { $0.kind == "campus" }.prefix(6)
        let gyms = merged.filter { $0.kind == "gym" }.prefix(8)
        return Array(campuses) + Array(gyms)
    }

    /// Renderable hubs: field pack unlocked by the newest campus, one hub
    /// per discovered campus, one crew per discovered gym.
    private static func build(from entries: [GeoCacheEntry]) -> [WhisperCommunity] {
        var out: [WhisperCommunity] = []
        let campuses = entries.filter { $0.kind == "campus" }
        if let first = campuses.first {
            out.append(contentsOf: Self.campusPack(near: first.name, address: first.address))
        }
        for entry in campuses {
            var hub = Self.campusCommunity(named: entry.name, distanceMeters: nil, address: entry.address)
            if !entry.origin.isEmpty { hub.origin = entry.origin }
            out.append(hub)
        }
        for entry in entries where entry.kind == "gym" {
            var gym = Self.gymCommunity(named: entry.name, distanceMeters: nil, address: entry.address)
            if !entry.origin.isEmpty { gym.origin = entry.origin }
            out.append(gym)
        }
        return out
    }

    private func loadCache() -> [WhisperCommunity]? {
        let entries = loadEntries()
        guard !entries.isEmpty else { return nil }
        let built = Self.build(from: entries)
        return built.isEmpty ? nil : built
    }
}

// MARK: - Near you section

/// "Near you" rail on the Communities screen — permission card, loading
/// pulse, or the live geo suggestions with their special reacts.
struct WhisperNearbyCommunitiesSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperNearbyCommunitiesService.shared
    @State private var users = WhisperUserService.shared
    @State private var joiningID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch service.phase {
            case .idle, .needsPermission:
                permissionCard
                    .padding(.horizontal, 16)
            case .loading:
                loadingRow
                    .padding(.horizontal, 16)
            case .ready:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(service.suggestions) { c in
                            NavigationLink(value: c) {
                                suggestionCard(c)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
            case .unavailable:
                unavailableRow
                    .padding(.horizontal, 16)
            }
        }
        .task { service.bootstrap() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Near you")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Image(systemName: "location.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Spacer()
            if service.phase == .ready {
                Button {
                    Haptics.tap()
                    Task { await service.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh nearby communities")
            }
        }
        .padding(.horizontal, 16)
    }

    private var permissionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.93, green: 0.42, blue: 0.22), Color(red: 1.00, green: 0.70, blue: 0.40)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "location.fill")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text("Find communities near you")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("A campus nearby unlocks Whisper Law & friends. Your gym gets its own crew.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                Task { await service.refresh(force: true) }
            } label: {
                Text("Enable")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Reading the neighborhood…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Spacer()
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
    }

    private var unavailableRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text("Nothing recognizable nearby yet — try again somewhere busier.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Spacer()
            Button {
                Haptics.tap()
                Task { await service.refresh(force: true) }
            } label: {
                Text("Retry")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
    }

    // MARK: - Suggestion card

    private func suggestionCard(_ c: WhisperCommunity) -> some View {
        let joined = isJoined(c)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    LinearGradient(
                        colors: c.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: c.symbol)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(.white)
                }
                if let react = c.specialReact {
                    Text(react)
                        .font(.system(size: 15))
                        .padding(5)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(6)
                }
            }
            .frame(width: 196, height: 104)
            .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 3) {
                Text(c.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                if let origin = c.origin {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9, weight: .bold))
                        Text(origin)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                }
                Button {
                    Haptics.tap()
                    Task { await toggleJoin(c) }
                } label: {
                    Text(joined ? "Joined" : "Join")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(joined ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(
                            joined ? Color.clear : WhisperTheme.ink(colorScheme),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: joined ? 1 : 0)
                        }
                        .opacity(joiningID == c.id ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(joiningID != nil)
                .padding(.top, 2)
            }
        }
        .frame(width: 196)
    }

    private func isJoined(_ c: WhisperCommunity) -> Bool {
        let interests = Set((users.me?.interests ?? []).map { $0.lowercased() })
        return interests.contains(c.name.lowercased())
    }

    private func toggleJoin(_ c: WhisperCommunity) async {
        guard joiningID == nil else { return }
        joiningID = c.id
        defer { joiningID = nil }
        let key = c.name.lowercased()
        var current = (users.me?.interests ?? []).map { $0 }
        if current.contains(where: { $0.lowercased() == key }) {
            current.removeAll { $0.lowercased() == key }
        } else {
            current.append(c.name)
        }
        _ = await users.updateInterests(current)
    }
}
