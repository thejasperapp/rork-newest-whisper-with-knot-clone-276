import SwiftUI
import MapKit
import CoreLocation

/// Recruiter scout map — a native MapKit command center replacing the old
/// spinning globe. Claimed territories become glowing avatar pins on a real
/// map, with a stat strip up top and a ranked "hot zones" breakdown below.
/// Tapping a pin or a zone card opens the territory detail sheet.
struct WhisperRecruiterGlobeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var recruiter = WhisperRecruiterService.shared
    @State private var groups: [RecruiterGroup] = []
    @State private var selectedGroup: RecruiterGroup?
    @State private var camera: MapCameraPosition = .automatic
    @State private var follows = WhisperFollowService.shared
    @State private var openThread: WhisperConversationSummary?
    @State private var openProfile: WhisperUserRow?
    /// Real geocoded coordinates per territory id — resolved once from the
    /// territory's name + cities and cached on-device, so every group pin
    /// sits at its actual place instead of a generic regional anchor.
    @State private var geoCoords: [String: CLLocationCoordinate2D] = [:]
    @State private var pinPulse: Bool = false
    /// First-open explainer + location permission slides (IG map style).
    @AppStorage("whisper.recruiterMap.introSeen") private var introSeen: Bool = false
    @State private var introPage: Int = 0
    @State private var introLocating: Bool = false
    @State private var introLocation = WhisperOneShotLocation()

    private var totalProspects: Int {
        groups.reduce(0) { $0 + $1.prospects.count }
    }

    /// The territory with the most pipeline prospects — the "hot zone".
    private var hotZone: RecruiterGroup? {
        groups.max { $0.prospects.count < $1.prospects.count }
    }

    var body: some View {
        VStack(spacing: 14) {
            statStrip

            if groups.isEmpty {
                emptyMapCard
            } else {
                mapCard
                zoneBreakdown
            }
        }
        .padding(.vertical, 12)
        .sheet(item: $selectedGroup) { group in
            RecruiterGroupDetailView(group: group)
        }
        .fullScreenCover(item: $openThread) { thread in
            WhisperDMThreadView(otherUserID: thread.otherUserID, otherUsername: thread.otherUsername)
        }
        .navigationDestination(item: $openProfile) { user in
            WhisperUserProfileView(user: user)
        }
        .task {
            await recruiter.refreshMyStatus()
            await recruiter.refreshAll()
            buildGroups()
            await geocodeTerritories()
        }
        .onChange(of: recruiter.territories.count) { _, _ in
            buildGroups()
            Task { await geocodeTerritories() }
        }
        .onChange(of: recruiter.prospects.count) { _, _ in
            buildGroups()
        }
        .overlay {
            if !introSeen {
                mapIntroOverlay
            }
        }
    }

    // MARK: - Intro slides (first open)

    /// Two IG-style cards over a dimmed map: what the scout map does, then
    /// the location permission ask. Never shown again once dismissed.
    private var mapIntroOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                if introPage == 0 {
                    ZStack {
                        introBubble(color: Color(red: 0.96, green: 0.62, blue: 0.04), offset: -40, size: 44)
                        introBubble(color: Color(red: 0.66, green: 0.33, blue: 0.91), offset: 40, size: 44)
                        introBubble(color: Color(red: 0.20, green: 0.83, blue: 0.60), offset: 0, size: 56)
                    }
                    .frame(height: 62)

                    Text("See your whole pipeline on the map")
                        .font(.title3.weight(.black))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        introRow(icon: "mappin.and.ellipse", bold: "Groups pin to their real spot.", text: "Placed by GPS when they're claimed — or wherever you drop the pin.")
                        introRow(icon: "person.2.fill", bold: "Faces, not regions.", text: "Every pin wears the scout's photo with a live prospect count.")
                        introRow(icon: "hand.tap.fill", bold: "Tap to open, pinch to zoom.", text: "Territory sheets show the pipeline behind each pin.")
                    }

                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { introPage = 1 }
                    } label: {
                        Text("Next")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                } else {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60))

                    Text("Pin territories with your location")
                        .font(.title3.weight(.black))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        introRow(icon: "location.fill", bold: "Claiming reads your GPS once.", text: "New territories land exactly where you're standing.")
                        introRow(icon: "eye.slash.fill", bold: "Nothing is tracked.", text: "Your location is only used the moment you place a pin — you can always drop it by hand instead.")
                        introRow(icon: "gearshape.fill", bold: "Change anytime.", text: "Manage access in Settings whenever you like.")
                    }

                    Button {
                        Haptics.tap()
                        guard !introLocating else { return }
                        introLocating = true
                        Task {
                            _ = await introLocation.request()
                            introLocating = false
                            withAnimation(.easeOut(duration: 0.25)) { introSeen = true }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if introLocating { ProgressView().tint(WhisperTheme.surface(colorScheme)) }
                            Text("Allow location")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(introLocating)
                    .padding(.top, 2)

                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.25)) { introSeen = true }
                    } label: {
                        Text("Not now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    private func introBubble(color: Color, offset: CGFloat, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle().strokeBorder(WhisperTheme.card(colorScheme), lineWidth: 3)
            }
            .offset(x: offset)
    }

    private func introRow(icon: String, bold: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 26, height: 26)
                .background(WhisperTheme.surface(colorScheme), in: Circle())
            Text("\(Text(bold).fontWeight(.bold)) \(text)")
                .font(.caption)
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Stat strip

    private var statStrip: some View {
        HStack(spacing: 8) {
            mapStat(
                value: "\(groups.count)",
                label: groups.count == 1 ? "Territory" : "Territories",
                icon: "flag.fill",
                tint: Color(red: 0.25, green: 0.62, blue: 1.0)
            )
            mapStat(
                value: "\(totalProspects)",
                label: "On the map",
                icon: "person.2.fill",
                tint: Color(red: 0.20, green: 0.83, blue: 0.60)
            )
            mapStat(
                value: hotZone.map { shortZoneName($0.name) } ?? "—",
                label: "Hot zone",
                icon: "flame.fill",
                tint: Color(red: 1.0, green: 0.58, blue: 0.25)
            )
        }
        .padding(.horizontal, 16)
    }

    private func shortZoneName(_ name: String) -> String {
        let first = name.components(separatedBy: .whitespaces).first ?? name
        return String(first.prefix(9))
    }

    private func mapStat(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Map

    private var mapCard: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(groups) { group in
                Annotation("", coordinate: pinCoordinate(for: group), anchor: .center) {
                    territoryPin(group)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .frame(height: 360)
        .onAppear {
            withAnimation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)) {
                pinPulse = true
            }
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(red: 0.20, green: 0.83, blue: 0.60))
                    .frame(width: 6, height: 6)
                Text("SCOUT MAP")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.62), in: Capsule())
            .padding(10)
        }
        .padding(.horizontal, 16)
    }

    /// Anchor-based territories in the same region share one coordinate —
    /// fan them out in a small deterministic ring so pins never stack.
    /// Territories with a REAL GPS pin sit exactly where they were placed.
    private func pinCoordinate(for group: RecruiterGroup) -> CLLocationCoordinate2D {
        if group.hasPreciseLocation {
            return CLLocationCoordinate2D(latitude: group.latitude, longitude: group.longitude)
        }
        let siblings = groups.filter { $0.region == group.region && !$0.hasPreciseLocation }
        guard siblings.count > 1,
              let index = siblings.firstIndex(where: { $0.id == group.id }), index > 0 else {
            return CLLocationCoordinate2D(latitude: group.latitude, longitude: group.longitude)
        }
        let angle = Double(index) * (2 * .pi / Double(max(2, siblings.count)))
        return CLLocationCoordinate2D(
            latitude: group.latitude + cos(angle) * 2.4,
            longitude: group.longitude + sin(angle) * 3.2
        )
    }

    private func territoryPin(_ group: RecruiterGroup) -> some View {
        Button {
            Haptics.tap()
            selectedGroup = group
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        // Radar pulse — the pin breathes so the map feels live.
                        Circle()
                            .strokeBorder(group.color.opacity(0.55), lineWidth: 1.5)
                            .frame(width: 52, height: 52)
                            .scaleEffect(pinPulse ? 1.5 : 0.85)
                            .opacity(pinPulse ? 0 : 0.9)
                        Circle()
                            .fill(group.color.opacity(0.28))
                            .frame(width: 52, height: 52)
                        Circle()
                            .strokeBorder(group.color, lineWidth: 2)
                            .frame(width: 42, height: 42)
                        WhisperAvatar(
                            username: group.recruiterUsername ?? "?",
                            size: 36,
                            imageURL: group.recruiterImageURL.flatMap { URL(string: $0) }
                        )
                    }
                    if !group.prospects.isEmpty {
                        Text("\(group.prospects.count)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18)
                            .frame(height: 18)
                            .background(group.color, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1)
                            }
                            .offset(x: 5, y: -3)
                    }
                }
                Text(group.name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.62), in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Zone breakdown

    private var zoneBreakdown: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Your zones")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Text("ranked by pipeline")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 16)

            let ranked = groups.sorted { $0.prospects.count > $1.prospects.count }
            let maxCount = max(1, ranked.first?.prospects.count ?? 1)
            VStack(spacing: 8) {
                ForEach(ranked) { group in
                    zoneCard(group, share: Double(group.prospects.count) / Double(maxCount))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func zoneCard(_ group: RecruiterGroup, share: Double) -> some View {
        Button {
            Haptics.tap()
            selectedGroup = group
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(group.color)
                        .frame(width: 8, height: 8)
                    Text(group.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text(group.region.capitalized)
                        .font(.system(size: 9, weight: .black))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(group.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(group.color.opacity(0.14), in: Capsule())
                    Spacer(minLength: 6)
                    Text("\(group.prospects.count)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(WhisperTheme.hairline(colorScheme))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [group.color.opacity(0.65), group.color],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * share))
                    }
                }
                .frame(height: 5)
            }
            .padding(12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyMapCard: some View {
        VStack(spacing: 12) {
            WhisperMeetDoodle(symbol: "map", height: 144)
            VStack(spacing: 4) {
                Text("Your map is waiting")
                    .font(.headline.weight(.black))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Claim the regions you scout and every territory becomes a live pin with its own pipeline.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Data

    private func buildGroups() {
        let myProfile = WhisperUserService.shared.me
        let myUserID = AccountStorage.currentUserID
        let myUsername = myProfile?.username ?? LeaderboardService.shared.savedUsername ?? "you"
        let myImageURL = myProfile?.profile_image_url

        groups = recruiter.territories.map { territory in
            let fallback = Self.coordinate(for: territory)
            let geo = geoCoords[territory.id]
            // Stored GPS pin (placed at claim time / by the admin) wins;
            // geocoded cache next; generic regional anchor last.
            let coord: (lat: Double, lon: Double)
            let precise = territory.latitude != nil && territory.longitude != nil
            if let la = territory.latitude, let lo = territory.longitude {
                coord = (la, lo)
            } else {
                coord = (geo?.latitude ?? fallback.lat, geo?.longitude ?? fallback.lon)
            }
            let territoryName = territory.name.lowercased()
            let territoryCities = (territory.cities ?? "").lowercased()
            let regionProspects = recruiter.prospects.filter { prospect in
                guard let loc = prospect.location?.lowercased(), !loc.isEmpty else { return false }
                return loc.contains(territoryName) || territoryCities.contains(loc) || territoryName.contains(loc)
            }
            return RecruiterGroup(
                id: territory.id,
                name: territory.name,
                region: territory.region,
                latitude: coord.lat,
                longitude: coord.lon,
                recruiterUserID: myUserID,
                recruiterUsername: myUsername,
                recruiterImageURL: myImageURL,
                prospects: regionProspects,
                color: WhisperRecruiterService.regionColor(territory.region),
                hasPreciseLocation: precise
            )
        }
        camera = .automatic
    }

    private static let geoCacheKey = "whisper.territory.geocache"

    /// Geocodes each territory (name + cities) to its real coordinate, one
    /// at a time with a courtesy delay, caching results on-device. Pins hold
    /// the regional anchor until the geocoder answers.
    private func geocodeTerritories() async {
        var cache = (UserDefaults.standard.dictionary(forKey: Self.geoCacheKey) as? [String: [Double]]) ?? [:]
        var changed = false
        for territory in recruiter.territories {
            // Stored GPS pins never need geocoding.
            if territory.latitude != nil, territory.longitude != nil { continue }
            let key = "\(territory.name)|\(territory.cities ?? "")".lowercased()
            if let hit = cache[key], hit.count == 2 {
                geoCoords[territory.id] = CLLocationCoordinate2D(latitude: hit[0], longitude: hit[1])
                continue
            }
            let query = [territory.name, territory.cities ?? ""]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            guard !query.isEmpty else { continue }
            do {
                let placemarks = try await CLGeocoder().geocodeAddressString(query)
                if let location = placemarks.first?.location {
                    geoCoords[territory.id] = location.coordinate
                    cache[key] = [location.coordinate.latitude, location.coordinate.longitude]
                    changed = true
                }
            } catch {
                // No match or rate-limited — the regional anchor stays.
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        if changed {
            UserDefaults.standard.set(cache, forKey: Self.geoCacheKey)
        }
        buildGroups()
    }

    static func coordinate(for territory: WhisperRecruiterService.TerritoryRow) -> (lat: Double, lon: Double) {
        let regionCoords: [String: (Double, Double)] = [
            "northeast": (40.7128, -74.0060),
            "southeast": (25.7617, -80.1918),
            "midwest": (41.8781, -87.6298),
            "southwest": (32.7767, -96.7970),
            "west": (34.0522, -118.2437),
            "northwest": (47.6062, -122.3321),
            "international": (51.5074, -0.1278),
            "other": (40.7128, -74.0060)
        ]
        return regionCoords[territory.region.lowercased()] ?? (40.7128, -74.0060)
    }
}

// MARK: - Recruiter group model

struct RecruiterGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    let recruiterUserID: String?
    let recruiterUsername: String?
    let recruiterImageURL: String?
    let prospects: [WhisperRecruiterService.ProspectRow]
    let color: Color
    /// True when the territory carries its own GPS pin (claimed on-site or
    /// hand-placed) — these never get fan-out offsets or geocoding.
    var hasPreciseLocation: Bool = false
}

// MARK: - Group detail sheet

struct RecruiterGroupDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let group: RecruiterGroup
    @State private var follows = WhisperFollowService.shared
    @State private var openThread: WhisperConversationSummary?

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        recruiterActions
                        if !group.prospects.isEmpty {
                            prospectsSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .fullScreenCover(item: $openThread) { thread in
                WhisperDMThreadView(otherUserID: thread.otherUserID, otherUsername: thread.otherUsername)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(group.color.opacity(0.15))
                    .frame(width: 86, height: 86)
                if let username = group.recruiterUsername, !username.isEmpty {
                    WhisperAvatar(
                        username: username,
                        size: 76,
                        imageURL: group.recruiterImageURL.flatMap { URL(string: $0) },
                        ring: true
                    )
                } else {
                    Image(systemName: "person.3.fill")
                        .font(.title2)
                        .foregroundStyle(group.color)
                }
            }

            VStack(spacing: 4) {
                Text(group.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .multilineTextAlignment(.center)
                Text("\(group.prospects.count) prospect\(group.prospects.count == 1 ? "" : "s") in this territory")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                if let username = group.recruiterUsername, !username.isEmpty {
                    Text("Scouted by @\(username)")
                        .font(.caption)
                        .foregroundStyle(group.color)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var recruiterActions: some View {
        if let recruiterID = group.recruiterUserID,
           let username = group.recruiterUsername,
           !username.isEmpty,
           recruiterID != AccountStorage.currentUserID {
            let isFollowing = follows.isFollowing(userID: recruiterID)
            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    if isFollowing {
                        Task { await follows.unfollow(userID: recruiterID) }
                    } else {
                        Task { await follows.follow(userID: recruiterID, username: username) }
                    }
                } label: {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isFollowing ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isFollowing ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme), in: Capsule())
                        .overlay {
                            if isFollowing {
                                Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    openThread = WhisperConversationSummary(
                        otherUserID: recruiterID,
                        otherUsername: username,
                        lastMessage: "",
                        lastDate: Date()
                    )
                } label: {
                    Text("Message")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var prospectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROSPECTS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .tracking(0.5)

            VStack(spacing: 10) {
                ForEach(group.prospects.prefix(10)) { prospect in
                    prospectRow(prospect)
                }
            }
        }
    }

    private func prospectRow(_ prospect: WhisperRecruiterService.ProspectRow) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1))
                Text(String((prospect.prospect_display_name ?? "?").prefix(1)).uppercased())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.prospect_display_name ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if let role = prospect.suggested_role, !role.isEmpty {
                    Text(role.capitalized)
                        .font(.caption2)
                        .foregroundStyle(group.color)
                }
                if let loc = prospect.location, !loc.isEmpty {
                    Text(loc)
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }

            Spacer()

            Text(prospect.status.capitalized)
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperRecruiterService.statusColor(prospect.status))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(WhisperRecruiterService.statusColor(prospect.status).opacity(0.12), in: Capsule())
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

#Preview {
    WhisperRecruiterGlobeView()
        .background(Color.black)
}
