import SwiftUI
import MapKit
import CoreLocation

// MARK: - Prospect card

/// One pipeline prospect — status pill menu, details, and delete.
struct WhisperRecruiterProspectCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var recruiter = WhisperRecruiterService.shared
    @State private var presentNotesSheet: Bool = false
    let prospect: WhisperRecruiterService.ProspectRow

    var body: some View {
        let color = WhisperRecruiterService.statusColor(prospect.status)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                WhisperAvatar(
                    username: prospect.prospect_username ?? prospect.prospect_display_name ?? "?",
                    size: 36,
                    imageURL: prospect.prospect_image_url.flatMap(URL.init(string:)),
                    ring: false
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(prospect.prospect_display_name ?? prospect.prospect_username ?? "Prospect")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    HStack(spacing: 6) {
                        if let username = prospect.prospect_username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        if let loc = prospect.location, !loc.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 9, weight: .bold))
                                Text(loc)
                                    .font(.caption)
                            }
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Status menu
                Menu {
                    ForEach(WhisperRecruiterService.prospectStatuses, id: \.value) { status in
                        Button(status.label) {
                            Task { await recruiter.updateProspectStatus(prospect, status: status.value) }
                        }
                    }
                    Divider()
                    Button("Remove", role: .destructive) {
                        Task { await recruiter.deleteProspect(prospect) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(WhisperRecruiterService.prospectStatuses.first { $0.value == prospect.status }?.label ?? prospect.status)
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.15), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                if let role = prospect.suggested_role {
                    Text(role.capitalized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(WhisperTheme.ink(colorScheme).opacity(0.08), in: Capsule())
                }
                if let niche = prospect.niche, !niche.isEmpty {
                    Text(niche)
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                if let rating = prospect.rating, rating > 0 {
                    HStack(spacing: 1) {
                        ForEach(0..<min(rating, 5), id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let notes = prospect.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.75))
                    .lineLimit(3)
            }
            if let shared = prospect.shared_notes, !shared.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                    Text(shared)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.75))
                        .lineLimit(3)
                    Spacer()
                }
            }

            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    presentNotesSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.caption.weight(.bold))
                        Text((prospect.notes?.isEmpty == false) || (prospect.shared_notes?.isEmpty == false) ? "Edit notes" : "Add notes")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .sheet(isPresented: $presentNotesSheet) {
            WhisperRecruiterProspectNotesSheet(prospect: prospect)
                .whisperSheetBorder()
        }
    }
}

// MARK: - Promote section

/// Search any user and promote them to coach / athlete / creator.
struct WhisperRecruiterPromoteSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var recruiter = WhisperRecruiterService.shared
    @State private var query: String = ""
    @State private var results: [WhisperUserRow] = []
    @State private var selected: WhisperUserRow?
    @State private var role: String = "coach"
    @State private var notes: String = ""
    @State private var promoting: Bool = false

    private let roles: [(value: String, label: String, icon: String)] = [
        ("coach", "Coach", "figure.strengthtraining.traditional"),
        ("athlete", "Athlete", "trophy.fill"),
        ("creator", "Creator", "checkmark.seal.fill")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PROMOTE A USER")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .tracking(0.5)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                TextField("Search by username…", text: $query)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .autocapitalization(.none)
                    .onChange(of: query) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.count >= 1 else {
                            results = []
                            return
                        }
                        Task {
                            let found = await WhisperUserService.shared.search(trimmed, limit: 8)
                            await MainActor.run { results = found }
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }

            if selected == nil && !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results.prefix(5), id: \.user_id) { user in
                        Button {
                            Haptics.tap()
                            selected = user
                            query = ""
                            results = []
                        } label: {
                            HStack(spacing: 10) {
                                WhisperAvatar(
                                    username: user.username,
                                    size: 28,
                                    imageURL: user.profile_image_url.flatMap(URL.init(string:)),
                                    ring: false
                                )
                                Text("@\(user.username)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            }

            if let user = selected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        WhisperAvatar(
                            username: user.username,
                            size: 34,
                            imageURL: user.profile_image_url.flatMap(URL.init(string:)),
                            ring: false
                        )
                        Text("@\(user.username)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Spacer()
                        Button {
                            selected = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        ForEach(roles, id: \.value) { r in
                            Button {
                                Haptics.tap()
                                role = r.value
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: r.icon)
                                        .font(.subheadline)
                                    Text(r.label)
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(role == r.value ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(role == r.value ? WhisperTheme.ink(colorScheme) : Color.clear, in: .rect(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(role == r.value ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField("Notes — why this promotion? (optional)", text: $notes, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(2...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }

                    Button {
                        Haptics.success()
                        promoting = true
                        Task {
                            let ok = await recruiter.promote(
                                userID: user.user_id,
                                username: user.username,
                                role: role,
                                notes: notes.isEmpty ? nil : notes
                            )
                            promoting = false
                            if ok {
                                selected = nil
                                notes = ""
                            }
                        }
                    } label: {
                        HStack {
                            if promoting {
                                ProgressView().tint(WhisperTheme.surface(colorScheme))
                            } else {
                                Text("Promote to \(roles.first { $0.value == role }?.label ?? role)")
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(promoting)
                }
                .padding(14)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            }

            // Past promotions
            if !recruiter.promotions.isEmpty {
                Text("YOUR PROMOTIONS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .tracking(0.5)
                    .padding(.top, 4)

                ForEach(recruiter.promotions, id: \.id) { promo in
                    HStack(spacing: 10) {
                        WhisperAvatar(username: promo.promoted_username, size: 30, imageURL: nil, ring: false)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(promo.promoted_username)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text(promo.role.capitalized)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        Spacer()
                        Button {
                            Haptics.warning()
                            Task { await recruiter.removePromotion(promo) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                }
            }
        }
    }
}

// MARK: - Targets section

/// Monthly recruitment goals with live progress from this month's promotions.
struct WhisperRecruiterTargetsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var recruiter = WhisperRecruiterService.shared
    @State private var coachTarget: Int = 0
    @State private var athleteTarget: Int = 0
    @State private var creatorTarget: Int = 0
    @State private var loaded: Bool = false

    var body: some View {
        let counts = recruiter.monthPromotionCounts()
        VStack(alignment: .leading, spacing: 14) {
            Text("MONTHLY TARGETS — \(WhisperRecruiterService.currentPeriod())")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .tracking(0.5)

            VStack(spacing: 14) {
                targetRow(label: "Coaches", value: $coachTarget, done: counts["coach"] ?? 0)
                targetRow(label: "Athletes", value: $athleteTarget, done: counts["athlete"] ?? 0)
                targetRow(label: "Creators", value: $creatorTarget, done: counts["creator"] ?? 0)

                Button {
                    Haptics.success()
                    Task {
                        await recruiter.saveTarget(coach: coachTarget, athlete: athleteTarget, creator: creatorTarget)
                    }
                } label: {
                    Text("Save targets")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            coachTarget = recruiter.target?.target_coach ?? 0
            athleteTarget = recruiter.target?.target_athlete ?? 0
            creatorTarget = recruiter.target?.target_creator ?? 0
        }
    }

    private func targetRow(label: String, value: Binding<Int>, done: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Stepper("", value: value, in: 0...50)
                    .labelsHidden()
                Text("\(done)/\(value.wrappedValue)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 40, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WhisperTheme.hairline(colorScheme).opacity(0.4))
                    Capsule()
                        .fill(Color(red: 0.13, green: 0.77, blue: 0.37))
                        .frame(width: value.wrappedValue > 0
                               ? geo.size.width * min(1, CGFloat(done) / CGFloat(value.wrappedValue))
                               : 0)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Add prospect sheet

struct WhisperRecruiterAddProspectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var recruiter = WhisperRecruiterService.shared

    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var location: String = ""
    @State private var niche: String = ""
    @State private var instagram: String = ""
    @State private var suggestedRole: String = "creator"
    @State private var notes: String = ""
    @State private var rating: Int = 0
    @State private var saving: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Name", text: $displayName, placeholder: "Who did you find?")
                    field("Whisper username (optional)", text: $username, placeholder: "@username if they're on Whisper")
                    field("Location", text: $location, placeholder: "e.g. Atlanta, GA")
                    field("Niche", text: $niche, placeholder: "e.g. Powerlifting, Sprinting")
                    field("Instagram (optional)", text: $instagram, placeholder: "@handle")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUGGESTED ROLE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        HStack(spacing: 8) {
                            ForEach(["coach", "athlete", "creator"], id: \.self) { r in
                                Button {
                                    Haptics.tap()
                                    suggestedRole = r
                                } label: {
                                    Text(r.capitalized)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(suggestedRole == r ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(suggestedRole == r ? WhisperTheme.ink(colorScheme) : Color.clear, in: Capsule())
                                        .overlay {
                                            Capsule().strokeBorder(suggestedRole == r ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("POTENTIAL")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    Haptics.tap()
                                    rating = star == rating ? 0 : star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.title3)
                                        .foregroundStyle(star <= rating
                                                         ? Color(red: 0.96, green: 0.62, blue: 0.04)
                                                         : WhisperTheme.muted(colorScheme))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    field("Notes", text: $notes, placeholder: "What stood out?", axis: .vertical)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
            .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
            .navigationTitle("New Prospect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.success()
                        saving = true
                        Task {
                            let ok = await recruiter.addProspect(
                                username: username.replacingOccurrences(of: "@", with: ""),
                                displayName: displayName,
                                location: location.isEmpty ? nil : location,
                                niche: niche.isEmpty ? nil : niche,
                                instagram: instagram.isEmpty ? nil : instagram,
                                suggestedRole: suggestedRole,
                                notes: notes.isEmpty ? nil : notes,
                                rating: rating > 0 ? rating : nil
                            )
                            saving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Add").font(.body.weight(.bold))
                        }
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .tracking(0.5)
            TextField(placeholder, text: text, axis: axis)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .autocapitalization(label.contains("username") || label.contains("Instagram") ? .none : .words)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
    }
}

// MARK: - Claim territory sheet

struct WhisperRecruiterClaimTerritorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var recruiter = WhisperRecruiterService.shared

    @State private var name: String = ""
    /// Derived automatically from the dropped pin — no manual selector.
    @State private var region: String = "other"
    @State private var cities: String = ""
    @State private var notes: String = ""
    @State private var saving: Bool = false

    // Map pin placement — the territory sits at the claimer's GPS, or
    // wherever they drop the pin. No region list.
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var mapCamera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 42, longitudeDelta: 42)
        )
    )
    @State private var locating: Bool = false
    @State private var placeLabel: String?
    @State private var locationHelper = WhisperOneShotLocation()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TERRITORY NAME")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        TextField("e.g. Atlanta Metro", text: $name)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("PIN YOUR TERRITORY")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .tracking(0.5)
                            Spacer()
                            if pinCoordinate != nil {
                                Text(WhisperRecruiterService.regionLabel(region))
                                    .font(.system(size: 9, weight: .black))
                                    .textCase(.uppercase)
                                    .tracking(0.6)
                                    .foregroundStyle(WhisperRecruiterService.regionColor(region))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(WhisperRecruiterService.regionColor(region).opacity(0.14), in: Capsule())
                            }
                        }
                        mapPicker
                        Button {
                            Haptics.tap()
                            useMyLocation()
                        } label: {
                            HStack(spacing: 6) {
                                if locating {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                Text(locating ? "Finding you…" : "Use my location")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(WhisperTheme.card(colorScheme), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(locating)
                        Text(pinCoordinate == nil
                             ? "Tap the map to drop your pin — territories sort by their real GPS spot, not a region list."
                             : (placeLabel ?? "Pin placed"))
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CITIES COVERED (OPTIONAL)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        TextField("Comma separated — e.g. Atlanta, Marietta", text: $cities)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTES (OPTIONAL)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        TextField("Gyms, meets, events to hit…", text: $notes, axis: .vertical)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(3...5)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
            .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
            .navigationTitle("Claim Territory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.success()
                        saving = true
                        Task {
                            let ok = await recruiter.claimTerritory(
                                name: name,
                                region: region,
                                cities: cities.isEmpty ? nil : cities,
                                notes: notes.isEmpty ? nil : notes,
                                latitude: pinCoordinate?.latitude,
                                longitude: pinCoordinate?.longitude
                            )
                            saving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Claim").font(.body.weight(.bold))
                        }
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pinCoordinate == nil || saving)
                }
            }
        }
    }

    // MARK: - Map placement

    private var mapPicker: some View {
        MapReader { proxy in
            Map(position: $mapCamera, interactionModes: [.pan, .zoom]) {
                if let pin = pinCoordinate {
                    Annotation("", coordinate: pin, anchor: .bottom) {
                        pinMarker
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .onTapGesture(coordinateSpace: .local) { point in
                if let coord = proxy.convert(point, from: .local) {
                    Haptics.tap()
                    place(coord)
                }
            }
        }
        .frame(height: 230)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var pinMarker: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(WhisperRecruiterService.regionColor(region))
                    .frame(width: 34, height: 34)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            Rectangle()
                .fill(WhisperRecruiterService.regionColor(region))
                .frame(width: 3, height: 8)
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }

    private func place(_ coord: CLLocationCoordinate2D) {
        pinCoordinate = coord
        Task { await deriveRegion(for: coord) }
    }

    private func useMyLocation() {
        guard !locating else { return }
        locating = true
        Task {
            let coord = await locationHelper.request()
            locating = false
            guard let coord else { return }
            Haptics.success()
            pinCoordinate = coord
            withAnimation(.easeInOut(duration: 0.6)) {
                mapCamera = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                ))
            }
            await deriveRegion(for: coord)
        }
    }

    /// Reverse-geocodes the pin into the color-bucket region automatically —
    /// the user never touches a region list. Also prefills the name/cities
    /// fields when they're still empty.
    private func deriveRegion(for coord: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let pm = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            region = "other"
            placeLabel = String(format: "%.3f, %.3f", coord.latitude, coord.longitude)
            return
        }
        if (pm.isoCountryCode ?? "US") != "US" {
            region = "international"
        } else {
            region = Self.regionBucket(forState: pm.administrativeArea ?? "")
        }
        let parts = [pm.locality, pm.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
        placeLabel = parts.isEmpty ? "Pin placed" : parts.joined(separator: ", ")
        if name.trimmingCharacters(in: .whitespaces).isEmpty, let locality = pm.locality, !locality.isEmpty {
            name = "\(locality) Metro"
        }
        if cities.isEmpty, let locality = pm.locality, !locality.isEmpty {
            cities = locality
        }
    }

    /// US state → the existing color-bucket regions (codes AND full names —
    /// CLPlacemark returns either depending on locale).
    nonisolated static func regionBucket(forState state: String) -> String {
        let s = state.lowercased()
        if ["me", "maine", "nh", "new hampshire", "vt", "vermont", "ma", "massachusetts", "ri", "rhode island", "ct", "connecticut", "ny", "new york", "nj", "new jersey", "pa", "pennsylvania"].contains(s) { return "northeast" }
        if ["de", "delaware", "md", "maryland", "dc", "district of columbia", "va", "virginia", "wv", "west virginia", "nc", "north carolina", "sc", "south carolina", "ga", "georgia", "fl", "florida", "ky", "kentucky", "tn", "tennessee", "al", "alabama", "ms", "mississippi", "ar", "arkansas", "la", "louisiana"].contains(s) { return "southeast" }
        if ["oh", "ohio", "in", "indiana", "il", "illinois", "mi", "michigan", "wi", "wisconsin", "mn", "minnesota", "ia", "iowa", "mo", "missouri", "nd", "north dakota", "sd", "south dakota", "ne", "nebraska", "ks", "kansas"].contains(s) { return "midwest" }
        if ["tx", "texas", "ok", "oklahoma", "nm", "new mexico", "az", "arizona"].contains(s) { return "southwest" }
        if ["ca", "california", "nv", "nevada", "ut", "utah", "co", "colorado", "hi", "hawaii"].contains(s) { return "west" }
        if ["wa", "washington", "or", "oregon", "id", "idaho", "mt", "montana", "wy", "wyoming", "ak", "alaska"].contains(s) { return "northwest" }
        return "other"
    }
}

// MARK: - One-shot location

/// Tiny async wrapper over CLLocationManager — requests when-in-use
/// permission if needed and resolves a single fix (or nil on denial/error).
@MainActor
final class WhisperOneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    func request() async -> CLLocationCoordinate2D? {
        manager.delegate = self
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }
        return await withCheckedContinuation { cont in
            if continuation != nil {
                cont.resume(returning: nil)
                return
            }
            continuation = cont
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.first?.coordinate
        Task { @MainActor in
            self.continuation?.resume(returning: coord)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.continuation?.resume(returning: nil)
                self.continuation = nil
            default:
                break
            }
        }
    }
}
