import SwiftUI
import MapKit
import CoreLocation

/// Encodes a nearby-restaurants map result inside a DM body, so Jasper can
/// send a friend a small map + restaurant list directly in chat. Tapping
/// a restaurant expands its menu — now generated per-viewer by
/// `EmberMenuService` so each user sees items ranked against THEIR own
/// remaining macros from `NutritionStore.shared`.
///
/// The wire payload stays backwards-compatible: older builds shipped each
/// place with a tiny inline `menu` array. Newer builds leave it empty and
/// resolve menus on demand. Tapping "Log" calls `NutritionStore.addMeal`
/// directly so the Whisper nutrition tab updates live (via the
/// `NutritionStore.didChange` notification).
nonisolated enum WhisperMapEmbed {
    static let prefix = "::whisper-map-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let lat: Double
        let lon: Double
        let radiusMeters: Double
        let places: [Place]
        /// Optional city label so receiving devices can pass it to
        /// `EmberMenuService` for better web lookups.
        let city: String?
        nonisolated var idValue: String { id }
        var coordinate: CLLocationCoordinate2D {
            .init(latitude: lat, longitude: lon)
        }

        init(id: String, title: String, lat: Double, lon: Double, radiusMeters: Double, places: [Place], city: String? = nil) {
            self.id = id
            self.title = title
            self.lat = lat
            self.lon = lon
            self.radiusMeters = radiusMeters
            self.places = places
            self.city = city
        }
    }

    nonisolated struct Place: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let name: String
        let category: String?
        let lat: Double
        let lon: Double
        /// Legacy field — newer builds leave this empty. The detail sheet
        /// resolves the real menu via `EmberMenuService` on expand.
        let menu: [MenuItem]
        var coordinate: CLLocationCoordinate2D {
            .init(latitude: lat, longitude: lon)
        }

        init(id: String, name: String, category: String?, lat: Double, lon: Double, menu: [MenuItem] = []) {
            self.id = id
            self.name = name
            self.category = category
            self.lat = lat
            self.lon = lon
            self.menu = menu
        }
    }

    nonisolated struct MenuItem: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let name: String
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload
    }
}

// MARK: - Inline card (DM bubble)

struct WhisperMapInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperMapEmbed.Payload
    let mine: Bool
    var onTap: () -> Void

    /// Fits the camera tightly around the user pin + all place pins so
    /// there's no dead space and the markers feel deliberately framed,
    /// rather than the old fixed-radius zoom which left a wide empty halo.
    private var region: MKCoordinateRegion {
        var lats: [Double] = [payload.lat]
        var lons: [Double] = [payload.lon]
        for p in payload.places {
            lats.append(p.lat)
            lons.append(p.lon)
        }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(
                center: payload.coordinate,
                latitudinalMeters: 1500,
                longitudinalMeters: 1500
            )
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Padding so pins aren't kissing the edge; floor so tiny clusters
        // still get a sensible zoom.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.012),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.012)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Short city/locality string for the secondary label — derived from
    /// `payload.city`, or falls back to the title's last comma component.
    private var locality: String? {
        if let c = payload.city, !c.isEmpty { return c }
        let parts = payload.title.split(separator: ",")
        guard parts.count > 1, let last = parts.last else { return nil }
        return last.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                mapHeader

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(payload.places.count) spots")
                            .font(.caption2.weight(.semibold))
                            .opacity(0.55)
                    }
                    placesList
                    HStack(spacing: 5) {
                        WhisperEmberBadge(size: 14)
                        Text("Tap — Jasper picks meals for your macros")
                            .font(.caption2.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .opacity(0.5)
                    }
                    .opacity(0.85)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(width: 286, alignment: .leading)
            .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
            .background(
                (mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme)),
                in: .rect(cornerRadius: 20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        mine ? Color.clear : WhisperTheme.hairline(colorScheme),
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var mapHeader: some View {
        Map(initialPosition: .region(region)) {
            Annotation("You", coordinate: payload.coordinate) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                }
            }
            ForEach(Array(payload.places.prefix(9).enumerated()), id: \.element.id) { idx, p in
                Annotation(p.name, coordinate: p.coordinate) {
                    NumberedPin(index: idx + 1)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .frame(height: 180)
        .allowsHitTesting(false)
        .clipShape(.rect(topLeadingRadius: 20, topTrailingRadius: 20))
        .overlay(alignment: .topLeading) {
            // Small floating locality tag in Apple-Maps share-card style.
            if let locality {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2.weight(.bold))
                    Text(locality)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
        }
    }

    /// Numbered list of the first few places, indices matching the map pins.
    private var placesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(payload.places.prefix(3).enumerated()), id: \.element.id) { idx, p in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.caption2.weight(.bold))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                        .background(
                            (mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)),
                            in: Circle()
                        )
                    Text(p.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let cat = p.category {
                        Text("·")
                            .font(.caption2)
                            .opacity(0.4)
                        Text(cat)
                            .font(.caption2)
                            .opacity(0.55)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            if payload.places.count > 3 {
                Text("+\(payload.places.count - 3) more")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.5)
                    .padding(.leading, 24)
            }
        }
    }
}

/// Small numbered pin used in the inline map. Mirrors the index next to
/// the place name below, so the eye can connect map → list immediately.
private struct NumberedPin: View {
    let index: Int
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            Text("\(index)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Detail sheet

/// Expands the map embed into a full-screen list of restaurants with
/// per-viewer menus generated by `EmberMenuService`. Items are ranked
/// against the viewer's remaining daily macros and filtered by chips.
struct WhisperMapDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperMapEmbed.Payload

    @State private var expanded: String?
    @State private var savedIDs: Set<String> = []
    @State private var savedToast: String?
    @State private var filter: EmberMenuService.MenuFilter = .all
    @State private var menus: [String: [EmberMenuService.MenuEntry]] = [:]
    @State private var loadingPlaceID: String?
    @State private var macrosTick: Int = 0

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: payload.coordinate,
            latitudinalMeters: max(payload.radiusMeters * 2.5, 1500),
            longitudinalMeters: max(payload.radiusMeters * 2.5, 1500)
        )
    }

    private var remaining: EmberMenuService.RemainingMacros {
        _ = macrosTick // re-evaluate when Whisper meals stream in
        let s = NutritionStore.shared
        return .init(
            calories: s.caloriesRemaining,
            protein: s.proteinRemaining,
            carbs: s.carbsRemaining,
            fat: s.fatRemaining
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Map(initialPosition: .region(region)) {
                            Annotation("You", coordinate: payload.coordinate) {
                                Image(systemName: "person.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.orange, in: Circle())
                            }
                            ForEach(payload.places) { p in
                                Marker(p.name, systemImage: "fork.knife", coordinate: p.coordinate)
                                    .tint(.red)
                            }
                        }
                        .frame(height: 220)
                        .clipShape(.rect(cornerRadius: 16))
                        .padding(.horizontal, 16)

                        macroSummaryBar
                            .padding(.horizontal, 16)

                        filterChips
                            .padding(.horizontal, 8)

                        VStack(spacing: 10) {
                            ForEach(payload.places) { p in
                                placeCard(p)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(payload.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task {
                // Pull fresh per-row meals from Supabase so "remaining" reflects
                // anything logged on the sister Whisper app since we last opened.
                await NutritionStore.shared.refreshFromWhisper()
                WhisperNutritionRemoteService.shared.startRealtimeSync()
                macrosTick &+= 1
            }
            .onReceive(NotificationCenter.default.publisher(for: NutritionStore.didChange)) { _ in
                macrosTick &+= 1
            }
            .overlay(alignment: .top) {
                if let toast = savedToast {
                    Text(toast)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.green, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var macroSummaryBar: some View {
        let r = remaining
        return HStack(spacing: 10) {
            WhisperEmberBadge(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Jasper sees")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text("\(r.calories) cal · \(Int(r.protein))p · \(Int(r.carbs))c · \(Int(r.fat))f left today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EmberMenuService.MenuFilter.allCases, id: \.self) { f in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.28)) { filter = f }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: f.icon)
                                .font(.caption2.weight(.bold))
                            Text(f.label)
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(filter == f ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                        .background(
                            filter == f ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func placeCard(_ p: WhisperMapEmbed.Place) -> some View {
        let isOpen = expanded == p.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32)) {
                    expanded = isOpen ? nil : p.id
                }
                if !isOpen, menus[p.id] == nil {
                    Task { await loadMenu(for: p) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.body.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(width: 36, height: 36)
                        .background(WhisperTheme.ink(colorScheme), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(1)
                        if let cat = p.category {
                            Text(cat)
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isOpen {
                Divider().background(WhisperTheme.hairline(colorScheme))
                expandedMenu(for: p)
            }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func expandedMenu(for p: WhisperMapEmbed.Place) -> some View {
        if let cached = menus[p.id] {
            let ranked = EmberMenuService.rank(cached, filter: filter, remaining: remaining)
            if ranked.isEmpty {
                Text("No items match this filter.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(ranked) { item in
                        menuRow(item, place: p)
                        if item.id != ranked.last?.id {
                            Divider().background(WhisperTheme.hairline(colorScheme))
                        }
                    }
                }
            }
        } else if loadingPlaceID == p.id {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Jasper is reading the menu…")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } else {
            Color.clear.frame(height: 1)
                .task { await loadMenu(for: p) }
        }
    }

    private func loadMenu(for p: WhisperMapEmbed.Place) async {
        loadingPlaceID = p.id
        let items = await EmberMenuService.shared.menu(
            for: p.name,
            category: p.category,
            city: payload.city
        )
        await MainActor.run {
            menus[p.id] = items
            if loadingPlaceID == p.id { loadingPlaceID = nil }
        }
    }

    private func menuRow(_ item: EmberMenuService.MenuEntry, place: WhisperMapEmbed.Place) -> some View {
        let saved = savedIDs.contains(item.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    if let tag = item.tag {
                        Text(tag)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WhisperTheme.surface(colorScheme), in: Capsule())
                            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                    }
                }
                Text("\(item.calories) cal · \(Int(item.protein))p · \(Int(item.carbs))c · \(Int(item.fat))f")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Menu {
                ForEach(MealType.allCases) { slot in
                    Button {
                        logItem(item, place: place, slot: slot)
                    } label: {
                        Label(slot.displayName, systemImage: slot.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: saved ? "checkmark" : "plus")
                    Text(saved ? "Logged" : "Log")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(saved ? .green : WhisperTheme.surface(colorScheme))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(saved ? Color.green.opacity(0.12) : WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .disabled(saved)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Wraps the menu-row log button: optimistic toast + cloud push for the
    /// chosen meal slot (breakfast/lunch/dinner/snack/drink).
    private func logItem(_ item: EmberMenuService.MenuEntry, place: WhisperMapEmbed.Place, slot: MealType) {
        guard !savedIDs.contains(item.id) else { return }
        Haptics.success()
        withAnimation(.spring(response: 0.3)) {
            _ = savedIDs.insert(item.id)
            savedToast = "Logged \(item.name) · \(slot.displayName)"
        }
        Task {
            _ = await logToMacros(item, place: place, slot: slot)
            try? await Task.sleep(for: .seconds(1.6))
            await MainActor.run {
                withAnimation { savedToast = nil }
            }
        }
    }

    /// Maps a meal slot to a canonical hour-of-day today so Whisper's
    /// hour-bucketed grouping (4-10 breakfast, 10-15 lunch, 15-21 dinner,
    /// else snack) puts the row in the right slot — Whisper's shared schema
    /// dropped `meal_type`, so we encode the slot via `eaten_at`. Drinks
    /// don't have a Whisper bucket, so they fall through to "now".
    private func timestamp(forSlot slot: MealType) -> Date {
        let now = Date()
        let cal = Calendar.current
        let hour: Int
        switch slot {
        case .breakfast: hour = 8
        case .lunch:     hour = 12
        case .dinner:    hour = 19
        case .snack:     hour = 15
        case .drink:     return now
        }
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = 30
        return cal.date(from: comps) ?? now
    }

    /// Adds the meal locally (NutritionStore + AccountStorage + widget defaults)
    /// AND pushes to Supabase so the Whisper RN app picks it up. Returns `true`
    /// when the cloud push succeeded — the caller surfaces a fallback toast on
    /// false so the user knows the macros stayed local-only.
    private func logToMacros(_ item: EmberMenuService.MenuEntry, place: WhisperMapEmbed.Place, slot: MealType) async -> Bool {
        let when = timestamp(forSlot: slot)
        let food = FoodItem(
            name: item.name,
            brand: "From Whisper",
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            mealType: slot,
            timestamp: when,
            icon: slot.icon
        )
        // Local write first so the macroSummaryBar and Whisper-side caches
        // update instantly even if the network is slow.
        NutritionStore.shared.addMealLocalOnly(food)
        // Direct await so we know if Supabase write actually landed.
        // Tag the row as a restaurant log so Whisper can badge it and skip
        // a duplicate insert if the same card round-trips through DM.
        return await WhisperNutritionRemoteService.shared.pushMeal(
            food,
            source: .whisperRestaurant,
            restaurantName: place.name,
            restaurantPlaceID: place.id
        )
    }
}
