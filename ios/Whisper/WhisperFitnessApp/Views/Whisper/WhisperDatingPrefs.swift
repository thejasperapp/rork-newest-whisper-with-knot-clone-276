import SwiftUI
import Supabase

/// Dating preferences — who you want to meet and how far you'll look.
/// Stored device-local for instant reads and synced to `whisper_dating_prefs`
/// (coarse coordinates only: rounded to ~1 km before they ever leave the
/// device). Mirrors web `lib/datingPrefs.ts` exactly.
nonisolated struct WhisperDatingPrefs: Codable, Equatable, Sendable {
    var gender: String? = nil          // woman | man | nonbinary
    var seeking: [String] = []         // empty = everyone
    var age: Int? = nil
    var ageMin: Int = 18
    var ageMax: Int = 99
    var radiusKm: Int = 50             // 0 = anywhere
    var intent: String? = nil          // relationship | casual | friends | open
    var lat: Double? = nil
    var lng: Double? = nil
    var cityLabel: String? = nil
    /// Round 77 — MY lifestyle answers by topic (smoking · drinking · kids ·
    /// faith · pets). Public to matches ("Doesn't smoke"). Mirrors web.
    var lifestyle: [String: String] = [:]
    /// Round 77 — DEALBREAKERS: topic → the answers I accept. A person who
    /// answered that topic with anything else is never paired with me or
    /// shown in my nearby list (enforced server-side in whisper_dating_fits);
    /// unanswered topics pass.
    var dealbreakers: [String: [String]] = [:]

    var hasLocation: Bool { lat != nil && lng != nil }
    var isAnywhere: Bool { radiusKm <= 0 }
    /// Anything set at all — the hub shows a "set who you want to meet" nudge until then.
    var isConfigured: Bool {
        gender != nil || !seeking.isEmpty || age != nil || intent != nil || hasLocation
    }

    static let genderOptions: [(id: String, label: String)] = [
        ("woman", "Woman"), ("man", "Man"), ("nonbinary", "Non-binary")
    ]
    static let seekingOptions: [(id: String, label: String)] = [
        ("woman", "Women"), ("man", "Men"), ("nonbinary", "Non-binary")
    ]
    static let intentOptions: [(id: String, label: String, emoji: String)] = [
        ("relationship", "A relationship", "💍"),
        ("casual", "Something casual", "🍸"),
        ("friends", "Friends first", "🤝"),
        ("open", "Open to anything", "✨")
    ]
    /// The distance stops on the slider — last stop is "anywhere".
    static let radiusStops: [Int] = [5, 10, 25, 50, 100, 250, 0]

    /// Lifestyle topics + their answer options — identical ids on web + SQL.
    static let lifestyleTopics: [(id: String, label: String, options: [(id: String, label: String)])] = [
        ("smoking", "Smoking", [("never", "Never"), ("sometimes", "Sometimes"), ("regular", "Regularly")]),
        ("drinking", "Drinking", [("never", "Never"), ("social", "Socially"), ("often", "Often")]),
        ("kids", "Kids", [("have", "Have kids"), ("want", "Want kids"), ("dont_want", "Don't want"), ("open", "Open")]),
        ("faith", "Faith", [("important", "Important to me"), ("spiritual", "Spiritual"), ("not_religious", "Not religious"), ("private", "Rather not say")]),
        ("pets", "Pets", [("have", "Have pets"), ("love", "Love them"), ("allergic", "Allergic"), ("none", "No pets")])
    ]

    static func lifestyleLabel(topic: String, value: String) -> String? {
        lifestyleTopics.first { $0.id == topic }?.options.first { $0.id == value }?.label
    }

    /// Does THIS person's lifestyle pass MY dealbreakers? Same rule as SQL:
    /// only an answered topic outside the accepted set fails.
    func dealbreakersAccept(_ theirLifestyle: [String: String]) -> Bool {
        for (topic, accepted) in dealbreakers where !accepted.isEmpty {
            if let theirs = theirLifestyle[topic], !theirs.isEmpty, !accepted.contains(theirs) {
                return false
            }
        }
        return true
    }

    /// "Doesn't smoke · Drinks socially" — the public lifestyle line.
    var lifestyleLine: String? {
        let parts: [String] = Self.lifestyleTopics.compactMap { t in
            guard let v = lifestyle[t.id], let label = Self.lifestyleLabel(topic: t.id, value: v) else { return nil }
            switch (t.id, v) {
            case ("smoking", "never"): return "Doesn't smoke"
            case ("smoking", _): return "Smokes \(label.lowercased())"
            case ("drinking", "never"): return "Doesn't drink"
            case ("drinking", _): return "Drinks \(label.lowercased())"
            default: return label
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func intentLabel(_ id: String?) -> String? {
        intentOptions.first { $0.id == id }?.label
    }

    /// One-line summary for chips: "Within 25 km · 24–34 · Women · A relationship".
    var summaryLine: String {
        var parts: [String] = []
        parts.append(isAnywhere ? "Anywhere" : "Within \(radiusKm) km")
        if ageMin > 18 || ageMax < 99 { parts.append("\(ageMin)–\(ageMax)") }
        if seeking.isEmpty {
            parts.append("Everyone")
        } else {
            parts.append(seeking.compactMap { id in Self.seekingOptions.first { $0.id == id }?.label }.joined(separator: " & "))
        }
        if let intent = Self.intentLabel(intent) { parts.append(intent) }
        return parts.joined(separator: " · ")
    }
}

/// One person inside my radius — coarse distance only (the server never
/// returns coordinates). Row shape of `whisper_dating_nearby()`.
nonisolated struct WhisperDatingNearbyPerson: Decodable, Sendable, Identifiable, Hashable {
    let user_id: String
    let username: String?
    let distance_km: Double?
    let age: Int?
    let gender: String?
    let intent: String?
    let city_label: String?
    /// Round 77 — verified dater + their public lifestyle answers.
    var verified: Bool? = nil
    var lifestyle: [String: String]? = nil
    var id: String { user_id.lowercased() }

    var distanceLabel: String? {
        guard let d = distance_km else { return nil }
        if d < 1 { return "under 1 km away" }
        return "\(Int(d.rounded())) km away"
    }
}

@MainActor
enum WhisperDatingPrefsStore {
    private static var key: String {
        "whisper-dating-prefs:\(AccountStorage.currentUserID.lowercased())"
    }
    private static var nearbyOnlyKey: String {
        "whisper-dating-nearby-only:\(AccountStorage.currentUserID.lowercased())"
    }

    /// Instant local read — every filter and the queue snapshot run off this.
    static func load() -> WhisperDatingPrefs {
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(WhisperDatingPrefs.self, from: data) else {
            return WhisperDatingPrefs()
        }
        return prefs
    }

    /// "Nearby only" hub filter — on by default once a location is saved.
    static var nearbyOnly: Bool {
        get { (UserDefaults.standard.object(forKey: nearbyOnlyKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: nearbyOnlyKey) }
    }

    /// Saves locally ALWAYS + upserts to Supabase best-effort (the table may
    /// not be migrated yet — the device copy still powers the hub filters).
    static func save(_ prefs: WhisperDatingPrefs) async {
        var clean = prefs
        clean.ageMin = max(18, min(clean.ageMin, 99))
        clean.ageMax = max(clean.ageMin, min(clean.ageMax, 99))
        if let a = clean.age { clean.age = max(18, min(a, 99)) }
        // Coarse coordinates — ~1 km cells; the exact fix never leaves the phone.
        if let lat = clean.lat, let lng = clean.lng {
            clean.lat = (lat * 100).rounded() / 100
            clean.lng = (lng * 100).rounded() / 100
        }
        if let data = try? JSONEncoder().encode(clean) {
            UserDefaults.standard.set(data, forKey: key)
        }
        let uid = AccountStorage.currentUserID.lowercased()
        guard !uid.isEmpty else { return }
        struct Row: Encodable, Sendable {
            let user_id: String
            let username: String?
            let gender: String?
            let seeking: [String]
            let age: Int?
            let age_min: Int
            let age_max: Int
            let radius_km: Int
            let intent: String?
            let lat: Double?
            let lng: Double?
            let city_label: String?
            let lifestyle: [String: String]
            let dealbreakers: [String: [String]]
            let updated_at: String
        }
        let row = Row(
            user_id: uid,
            username: LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username,
            gender: clean.gender,
            seeking: clean.seeking,
            age: clean.age,
            age_min: clean.ageMin,
            age_max: clean.ageMax,
            radius_km: clean.radiusKm,
            intent: clean.intent,
            lat: clean.lat,
            lng: clean.lng,
            city_label: clean.cityLabel,
            lifestyle: clean.lifestyle,
            dealbreakers: clean.dealbreakers,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            _ = try await SupabaseService.shared.client
                .from("whisper_dating_prefs")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            // Pre-dating-v2 databases don't have the lifestyle columns yet —
            // save the rest so the radius/age/intent still sync.
            struct LegacyRow: Encodable, Sendable {
                let user_id: String
                let username: String?
                let gender: String?
                let seeking: [String]
                let age: Int?
                let age_min: Int
                let age_max: Int
                let radius_km: Int
                let intent: String?
                let lat: Double?
                let lng: Double?
                let city_label: String?
                let updated_at: String
            }
            let legacy = LegacyRow(
                user_id: row.user_id, username: row.username, gender: row.gender, seeking: row.seeking,
                age: row.age, age_min: row.age_min, age_max: row.age_max, radius_km: row.radius_km,
                intent: row.intent, lat: row.lat, lng: row.lng, city_label: row.city_label, updated_at: row.updated_at
            )
            _ = try? await SupabaseService.shared.client
                .from("whisper_dating_prefs")
                .upsert(legacy, onConflict: "user_id")
                .execute()
        }
    }

    /// Cloud pull (best-effort) — a saved row wins over an empty device.
    static func syncFromCloud() async -> WhisperDatingPrefs {
        let uid = AccountStorage.currentUserID.lowercased()
        guard !uid.isEmpty else { return load() }
        struct Row: Decodable, Sendable {
            let gender: String?
            let seeking: [String]?
            let age: Int?
            let age_min: Int?
            let age_max: Int?
            let radius_km: Int?
            let intent: String?
            let lat: Double?
            let lng: Double?
            let city_label: String?
            let lifestyle: [String: String]?
            let dealbreakers: [String: [String]]?
        }
        let rows: [Row]? = try? await SupabaseService.shared.client
            .from("whisper_dating_prefs")
            .select()
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value
        guard let r = rows?.first else { return load() }
        let prefs = WhisperDatingPrefs(
            gender: r.gender,
            seeking: r.seeking ?? [],
            age: r.age,
            ageMin: r.age_min ?? 18,
            ageMax: r.age_max ?? 99,
            radiusKm: r.radius_km ?? 50,
            intent: r.intent,
            lat: r.lat,
            lng: r.lng,
            cityLabel: r.city_label,
            lifestyle: r.lifestyle ?? [:],
            dealbreakers: r.dealbreakers ?? [:]
        )
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return prefs
    }

    /// People inside my radius (mutual fit) — empty until the migration runs
    /// or until I've saved preferences.
    static func fetchNearby() async -> [WhisperDatingNearbyPerson] {
        let rows: [WhisperDatingNearbyPerson]? = try? await SupabaseService.shared.client
            .rpc("whisper_dating_nearby")
            .execute()
            .value
        return rows ?? []
    }
}

/// The preferences sheet — who you want to meet, age range, distance radius,
/// what you're looking for, and a coarse location. Mirrors web `DatingPrefsDialog`.
struct WhisperDatingPrefsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var onSaved: (() -> Void)? = nil

    @State private var prefs: WhisperDatingPrefs = WhisperDatingPrefs()
    @State private var radiusIndex: Double = 3
    @State private var locating: Bool = false
    @State private var locationError: String? = nil
    @State private var saving: Bool = false

    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            WhisperEmberMascot(size: 44, expression: .curious, palette: .cupidPink, smitten: true)
                            Text("Who you want to meet, and how far you'll look. Your exact spot never leaves your phone — only a ~1 km area, and other people only ever see a rounded distance.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        section("I AM") {
                            chipRow(WhisperDatingPrefs.genderOptions.map { ($0.id, $0.label) },
                                    isOn: { prefs.gender == $0 },
                                    toggle: { prefs.gender = prefs.gender == $0 ? nil : $0 })
                        }

                        section("SHOW ME") {
                            chipRow([("everyone", "Everyone")] + WhisperDatingPrefs.seekingOptions.map { ($0.id, $0.label) },
                                    isOn: { id in id == "everyone" ? prefs.seeking.isEmpty : prefs.seeking.contains(id) },
                                    toggle: { id in
                                        if id == "everyone" {
                                            prefs.seeking = []
                                        } else if let i = prefs.seeking.firstIndex(of: id) {
                                            prefs.seeking.remove(at: i)
                                        } else {
                                            prefs.seeking.append(id)
                                        }
                                    })
                        }

                        section("MY AGE") {
                            HStack(spacing: 14) {
                                Text(prefs.age.map(String.init) ?? "—")
                                    .font(.system(size: 30, weight: .black))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .frame(minWidth: 52, alignment: .leading)
                                    .contentTransition(.numericText())
                                Stepper("", value: Binding(
                                    get: { prefs.age ?? 25 },
                                    set: { prefs.age = max(18, min($0, 99)) }
                                ), in: 18...99)
                                .labelsHidden()
                                .tint(rose)
                                if prefs.age == nil {
                                    Text("Tap + to set")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                                Spacer()
                            }
                        }

                        section("AGE RANGE · \(prefs.ageMin)–\(prefs.ageMax)") {
                            VStack(spacing: 6) {
                                labeledSlider("Youngest", value: Binding(
                                    get: { Double(prefs.ageMin) },
                                    set: { prefs.ageMin = Int($0.rounded()); if prefs.ageMax < prefs.ageMin { prefs.ageMax = prefs.ageMin } }
                                ), range: 18...99)
                                labeledSlider("Oldest", value: Binding(
                                    get: { Double(prefs.ageMax) },
                                    set: { prefs.ageMax = Int($0.rounded()); if prefs.ageMin > prefs.ageMax { prefs.ageMin = prefs.ageMax } }
                                ), range: 18...99)
                            }
                        }

                        section("DISTANCE · \(radiusLabel)") {
                            VStack(alignment: .leading, spacing: 4) {
                                Slider(value: $radiusIndex, in: 0...Double(WhisperDatingPrefs.radiusStops.count - 1), step: 1)
                                    .tint(rose)
                                    .onChange(of: radiusIndex) { _, v in
                                        prefs.radiusKm = WhisperDatingPrefs.radiusStops[Int(v.rounded())]
                                    }
                                HStack {
                                    Text("5 km")
                                    Spacer()
                                    Text("Anywhere")
                                }
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                if !prefs.hasLocation, !prefs.isAnywhere {
                                    Text("Set your location below so the radius can actually filter.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(rose)
                                }
                            }
                        }

                        section("LOOKING FOR") {
                            chipRow(WhisperDatingPrefs.intentOptions.map { ($0.id, "\($0.emoji) \($0.label)") },
                                    isOn: { prefs.intent == $0 },
                                    toggle: { prefs.intent = prefs.intent == $0 ? nil : $0 })
                        }

                        section("MY LIFESTYLE") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Shown to your matches as a short line — \"Doesn't smoke · Drinks socially\".")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                ForEach(WhisperDatingPrefs.lifestyleTopics, id: \.id) { topic in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(topic.label)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        chipRow(topic.options.map { ($0.id, $0.label) },
                                                isOn: { prefs.lifestyle[topic.id] == $0 },
                                                toggle: { v in
                                                    if prefs.lifestyle[topic.id] == v { prefs.lifestyle.removeValue(forKey: topic.id) } else { prefs.lifestyle[topic.id] = v }
                                                })
                                    }
                                }
                            }
                        }

                        section("DEALBREAKERS") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Pick what you'll accept per topic. Anyone who answered otherwise is never paired with you — in the blind-date queue or nearby. People who left a topic blank still pass.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(WhisperDatingPrefs.lifestyleTopics, id: \.id) { topic in
                                    let active = !(prefs.dealbreakers[topic.id] ?? []).isEmpty
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Text(topic.label)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                            if active {
                                                Text("DEALBREAKER")
                                                    .font(.system(size: 9, weight: .heavy))
                                                    .tracking(0.6)
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(rose, in: Capsule())
                                            } else {
                                                Text("Any answer OK")
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                            }
                                        }
                                        chipRow(topic.options.map { ($0.id, "OK: \($0.label)") },
                                                isOn: { (prefs.dealbreakers[topic.id] ?? []).contains($0) },
                                                toggle: { v in
                                                    var set = prefs.dealbreakers[topic.id] ?? []
                                                    if let i = set.firstIndex(of: v) { set.remove(at: i) } else { set.append(v) }
                                                    if set.isEmpty { prefs.dealbreakers.removeValue(forKey: topic.id) } else { prefs.dealbreakers[topic.id] = set }
                                                })
                                    }
                                }
                            }
                        }

                        section("LOCATION") {
                            HStack(spacing: 10) {
                                Image(systemName: prefs.hasLocation ? "location.fill" : "location.slash")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(prefs.hasLocation ? rose : WhisperTheme.muted(colorScheme))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prefs.cityLabel ?? (prefs.hasLocation ? "Location saved" : "Not set"))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    Text(prefs.hasLocation ? "Saved as a ~1 km area, never your exact spot." : "Used only to measure distance to other daters.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                                Spacer(minLength: 0)
                                Button {
                                    Haptics.tap()
                                    Task { await useMyLocation() }
                                } label: {
                                    HStack(spacing: 5) {
                                        if locating {
                                            ProgressView().controlSize(.mini).tint(.white)
                                        } else {
                                            Image(systemName: "location.fill").font(.system(size: 10, weight: .bold))
                                        }
                                        Text(prefs.hasLocation ? "Update" : "Use my location")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(rose))
                                }
                                .buttonStyle(.plain)
                                .disabled(locating)
                            }
                            if let locationError {
                                Text(locationError)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(rose)
                            }
                            if prefs.hasLocation {
                                Button("Remove location") {
                                    Haptics.tap()
                                    prefs.lat = nil
                                    prefs.lng = nil
                                    prefs.cityLabel = nil
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }

                        Button {
                            Haptics.tap()
                            saving = true
                            Task {
                                await WhisperDatingPrefsStore.save(prefs)
                                saving = false
                                onSaved?()
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if saving {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else {
                                    Image(systemName: "heart.fill").font(.system(size: 13, weight: .bold))
                                }
                                Text("Save preferences")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(rose))
                        }
                        .buttonStyle(.plain)
                        .disabled(saving)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Dating preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            prefs = WhisperDatingPrefsStore.load()
            radiusIndex = Double(WhisperDatingPrefs.radiusStops.firstIndex(of: prefs.radiusKm) ?? 3)
            let cloud = await WhisperDatingPrefsStore.syncFromCloud()
            if cloud.isConfigured, !prefs.isConfigured {
                prefs = cloud
                radiusIndex = Double(WhisperDatingPrefs.radiusStops.firstIndex(of: prefs.radiusKm) ?? 3)
            }
        }
    }

    private var radiusLabel: String {
        prefs.isAnywhere ? "Anywhere" : "Within \(prefs.radiusKm) km"
    }

    private func useMyLocation() async {
        locating = true
        locationError = nil
        do {
            let ctx = try await EmberLocationService.shared.requestCurrentContext()
            prefs.lat = (ctx.latitude * 100).rounded() / 100
            prefs.lng = (ctx.longitude * 100).rounded() / 100
            let parts = [ctx.city, ctx.region].compactMap { $0 }.filter { !$0.isEmpty }
            prefs.cityLabel = parts.isEmpty ? nil : parts.joined(separator: ", ")
            Haptics.success()
        } catch {
            locationError = "Couldn't get your location — allow it in Settings, or leave distance on Anywhere."
        }
        locating = false
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .black))
                .tracking(1.3)
                .foregroundStyle(rose)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(rose.opacity(0.18), lineWidth: 1)
        }
    }

    private func chipRow(_ options: [(String, String)], isOn: @escaping (String) -> Bool, toggle: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.0) { id, label in
                let on = isOn(id)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { toggle(id) }
                } label: {
                    Text(label)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(on ? .white : rose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(on ? rose : rose.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(rose.opacity(on ? 0 : 0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(width: 66, alignment: .leading)
            Slider(value: value, in: range, step: 1).tint(rose)
            Text("\(Int(value.wrappedValue.rounded()))")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 26, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
