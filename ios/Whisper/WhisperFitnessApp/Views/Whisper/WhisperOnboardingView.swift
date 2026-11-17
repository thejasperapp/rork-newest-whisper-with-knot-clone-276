import SwiftUI
import PhotosUI
import UIKit

/// Whisper's onboarding — the Instagram / Threads flow, one decision per
/// screen, mirrored 1:1 with the web flow:
///
///   0. Profile      — photo, username (required when missing), name, bio
///   1. Communities  — join real communities from the catalog (Dating featured)
///   2. People       — follow suggested accounts (+ contacts)
///   3. Jasper       — optional: link the Jasper account (one tap → Allow)
///   4. Guidelines   — how Whisper works + agree to the Terms
///   5. Done         — recap, then into the app
///
/// Community picks are stored as interests (lowercased community names) —
/// the membership signal both apps read. Completing the flow inserts the
/// `whisper_profiles` row so the user is searchable on Explore.
struct WhisperOnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var users = WhisperUserService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var auth = AuthenticationService.shared
    @State private var blocks = WhisperBlockService.shared

    @State private var step: Int = 0
    @State private var isSubmitting: Bool = false

    // Step 0 — profile
    @State private var displayNameDraft: String = ""
    @State private var bio: String = ""
    @State private var hydratedUsername: String?
    @State private var usernameDraft: String = ""
    @State private var usernameStatus: UsernameStatus = .idle
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var needsUsernamePicker: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var localPhotoData: Data?
    @State private var isUploadingPhoto: Bool = false
    @State private var photoErrorMessage: String?

    // Step 1 — communities (catalog ids)
    @State private var selectedCommunities: Set<String> = []

    // Step 2 — people
    @State private var selectedFollows: Set<String> = []
    @State private var suggestions: [WhisperUserRow] = []
    @State private var presentFindFriends: Bool = false

    // Step 3 — Jasper
    @State private var jasperLinked: Bool = false

    // Step 5 — celebration
    @State private var celebrationMark: Bool = false

    private static let stepCount: Int = 5

    private enum UsernameStatus: Equatable {
        case idle
        case checking
        case available
        case taken
        case invalid(String)
    }

    private var displayUsername: String {
        LeaderboardService.shared.savedUsername
            ?? hydratedUsername
            ?? auth.currentUser.username
            ?? "you"
    }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var cardBG: Color { WhisperTheme.card(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }
    private var surfaceBG: Color { WhisperTheme.surface(colorScheme) }

    private var skippable: Bool { step >= 1 && step <= 3 }

    var body: some View {
        ZStack {
            surfaceBG.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if step < 5 { progressBar }
                ScrollView {
                    VStack(spacing: 0) {
                        stepContent
                            .id(step)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 150)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            VStack {
                Spacer()
                bottomBar
            }
            .ignoresSafeArea(.keyboard)

            if step == 5 {
                WhisperConfettiBurst()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .whisperEdgeBack(isEnabled: step > 0 && step < 5, revealPresentation: false) { go(to: step - 1) }
        .interactiveDismissDisabled(true)
        .task { await hydrate() }
        .sheet(isPresented: $presentFindFriends) {
            WhisperFindFriendsView()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            ZStack(alignment: .leading) {
                Color.clear.frame(width: 64, height: 40)
                if step > 0 && step < 5 {
                    Button {
                        Haptics.tap()
                        go(to: step - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ink)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
            }
            Spacer()
            WhisperWordmark(size: 26)
            Spacer()
            ZStack(alignment: .trailing) {
                Color.clear.frame(width: 64, height: 40)
                if skippable {
                    Button {
                        Haptics.tap()
                        go(to: step + 1)
                    } label: {
                        Text("Skip")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(muted)
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.stepCount, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? ink : hairline)
                    .frame(height: 3)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: profileStep
        case 1: communitiesStep
        case 2: peopleStep
        case 3: jasperStep
        case 4: guidelinesStep
        default: doneStep
        }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 22)
    }

    // MARK: - Bottom bar (one primary action — Instagram grammar)

    private var primaryLabel: String {
        if isSubmitting { return "Saving…" }
        switch step {
        case 1:
            return selectedCommunities.isEmpty ? "Continue" : "Join \(selectedCommunities.count) & continue"
        case 2:
            return selectedFollows.isEmpty ? "Continue" : "Follow \(selectedFollows.count) & continue"
        case 3:
            return jasperLinked ? "Continue" : "Continue without Jasper"
        case 4:
            return "Agree and continue"
        case 5:
            return "Enter Whisper"
        default:
            return "Next"
        }
    }

    private var canAdvance: Bool {
        if isSubmitting { return false }
        if step == 0 && needsUsernamePicker { return usernameStatus == .available }
        return true
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if step == 4 {
                legalLine
            }
            Button {
                Haptics.tap()
                advance()
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(surfaceBG) }
                    Text(primaryLabel)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(surfaceBG)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canAdvance ? ink : muted, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            surfaceBG
                .overlay(alignment: .top) { Divider().background(hairline) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var legalLine: some View {
        HStack(spacing: 0) {
            Text("By continuing you agree to Whisper's ")
            Link("Terms", destination: URL(string: "https://www.mydailywhisper.com/terms")!)
                .foregroundStyle(ink)
                .fontWeight(.semibold)
            Text(" and ")
            Link("Privacy Policy", destination: URL(string: "https://www.mydailywhisper.com/privacy")!)
                .foregroundStyle(ink)
                .fontWeight(.semibold)
            Text(".")
        }
        .font(.caption2)
        .foregroundStyle(muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Navigation

    private func go(to next: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step = max(0, min(5, next))
        }
    }

    private func advance() {
        switch step {
        case 0:
            Task {
                await saveProfileStep()
                await MainActor.run { go(to: 1) }
            }
        case 1, 2, 3:
            go(to: step + 1)
        case 4:
            Task { await finish() }
        default:
            Haptics.success()
            dismiss()
        }
    }

    private func hydrate() async {
        displayNameDraft = auth.currentUser.displayName ?? ""
        if LeaderboardService.shared.savedUsername == nil {
            hydratedUsername = await LeaderboardService.shared.hydrateUsernameFromSupabase()
        }
        needsUsernamePicker = (LeaderboardService.shared.savedUsername ?? hydratedUsername ?? "").isEmpty
        if needsUsernamePicker {
            usernameDraft = auth.currentUser.username ?? ""
            if !usernameDraft.isEmpty { scheduleUsernameCheck() }
        }
        suggestions = await users.suggestions(limit: 18)
    }

    // MARK: - Step 0: Profile

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader("Create your profile", "This is how people will find and recognize you on Whisper.")

            VStack(spacing: 10) {
                profilePhotoPicker
                Text(localPhotoData == nil && (auth.currentUser.profileImageURL ?? "").isEmpty
                     ? "Add a photo"
                     : "Change photo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)

            if let photoErrorMessage {
                Text(photoErrorMessage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if needsUsernamePicker {
                usernameSection
            } else {
                fieldLabel("Username")
                HStack(spacing: 8) {
                    Text("@\(displayUsername)")
                        .font(.body)
                        .foregroundStyle(ink)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(cardBG, in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(hairline, lineWidth: 1) }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Name")
                TextField("Your name", text: $displayNameDraft)
                    .textInputAutocapitalization(.words)
                    .font(.body)
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(cardBG, in: .rect(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(hairline, lineWidth: 1) }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Bio")
                ZStack(alignment: .topLeading) {
                    if bio.isEmpty {
                        Text("A line about you")
                            .font(.body)
                            .foregroundStyle(muted)
                            .padding(.top, 12)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $bio)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .foregroundStyle(ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .frame(minHeight: 96)
                }
                .background(cardBG, in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(hairline, lineWidth: 1) }
                HStack {
                    Spacer()
                    Text("\(bio.count)/150 · optional")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(muted)
                }
            }
            .onChange(of: bio) { _, new in
                if new.count > 150 { bio = String(new.prefix(150)) }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(muted)
    }

    private var profilePhotoPicker: some View {
        PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                if let data = localPhotoData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                } else if let url = auth.currentUser.profileImageURL.flatMap(URL.init(string:)) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            WhisperAvatar(username: displayUsername, size: 104, ring: false)
                        }
                    }
                    .frame(width: 104, height: 104)
                    .clipShape(Circle())
                } else {
                    WhisperAvatar(username: displayUsername, size: 104, ring: false)
                }
                ZStack {
                    Circle().fill(ink)
                    if isUploadingPhoto {
                        ProgressView().tint(surfaceBG).scaleEffect(0.75)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(surfaceBG)
                    }
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(surfaceBG, lineWidth: 3))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add profile photo")
        .onChange(of: pickedPhotoItem) { _, item in
            guard let item else { return }
            handlePickedPhoto(item)
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) {
        photoErrorMessage = nil
        isUploadingPhoto = true
        Task {
            defer { isUploadingPhoto = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    photoErrorMessage = "Couldn't read that photo. Try another."
                    return
                }
                await MainActor.run { localPhotoData = data }
                let jpeg = Self.normalizedJPEG(from: data) ?? data
                _ = try await auth.uploadProfileImage(jpeg)
                await MainActor.run { pickedPhotoItem = nil }
            } catch {
                photoErrorMessage = error.localizedDescription
            }
        }
    }

    private static func normalizedJPEG(from data: Data, maxDimension: CGFloat = 1024) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale: CGFloat = min(1.0, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }

    // MARK: Username picker (only when the account has no handle yet)

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Username")
            HStack(spacing: 8) {
                Text("@")
                    .font(.body.weight(.bold))
                    .foregroundStyle(muted)
                TextField("username", text: $usernameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.body)
                    .foregroundStyle(ink)
                    .onChange(of: usernameDraft) { _, _ in scheduleUsernameCheck() }
                Spacer()
                usernameStatusBadge
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(cardBG, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(hairline, lineWidth: 1) }
            usernameStatusLine
        }
    }

    @ViewBuilder
    private var usernameStatusBadge: some View {
        switch usernameStatus {
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .taken, .invalid:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var usernameStatusLine: some View {
        switch usernameStatus {
        case .available:
            Text("@\(usernameDraft.lowercased()) is available")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
        case .taken:
            Text("That username is taken — try another.")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
        case .invalid(let reason):
            Text(reason)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
        case .checking, .idle:
            Text("Lowercase letters, numbers, _ and . — 3 to 20 characters.")
                .font(.caption2)
                .foregroundStyle(muted)
        }
    }

    private func scheduleUsernameCheck() {
        usernameCheckTask?.cancel()
        let raw = usernameDraft
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        if normalized != raw { usernameDraft = normalized }
        guard !normalized.isEmpty else {
            usernameStatus = .idle
            return
        }
        if normalized.count < 3 || normalized.count > 20 {
            usernameStatus = .invalid("Must be 3–20 characters.")
            return
        }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_."))
        guard normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            usernameStatus = .invalid("Letters, numbers, dot and underscore only.")
            return
        }
        usernameStatus = .checking
        usernameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            let ok = await LeaderboardService.shared.isUsernameAvailable(normalized)
            if Task.isCancelled { return }
            await MainActor.run { usernameStatus = ok ? .available : .taken }
        }
    }

    /// Reserves the username (when picked here) and mirrors the display name
    /// into the auth profile so the profile row is born with both.
    private func saveProfileStep() async {
        if needsUsernamePicker, usernameStatus == .available,
           let saved = LeaderboardService.shared.setUsername(usernameDraft) {
            _ = await LeaderboardService.shared.reserveUsername(saved)
            await MainActor.run {
                var u = AuthenticationService.shared.currentUser
                u.username = saved
                AuthenticationService.shared.currentUser = u
                AuthenticationService.shared.saveCurrentUser()
                hydratedUsername = saved
            }
        }
        let name = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != auth.currentUser.displayName {
            await MainActor.run {
                var u = AuthenticationService.shared.currentUser
                u.displayName = name
                AuthenticationService.shared.currentUser = u
                AuthenticationService.shared.saveCurrentUser()
            }
        }
    }

    // MARK: - Step 1: Communities (the real catalog, Dating featured)

    /// Display groups over the shared catalog ids — anything not listed lands in "More".
    private static let communitySections: [(title: String, ids: [String])] = [
        ("Fitness & wellness", ["workouts", "running", "lifting", "yoga", "mobility", "hiit", "recovery", "sleep", "nutrition", "hydration", "mindset", "mindfulness", "outdoors", "hiking", "climbing", "cycling", "swimming", "stretching", "progress"]),
        ("Culture & interests", ["food", "cooking", "coffee", "books", "music", "movies", "tv", "gaming", "anime", "sports", "basketball", "football", "soccer", "travel", "photography", "art", "design", "fashion", "beauty", "comedy"]),
        ("Work & mind", ["tech", "ai", "coding", "startups", "finance", "business", "productivity", "study", "languages", "mentalhealth", "science", "philosophy", "history", "writing", "news"]),
        ("Life", ["parenting", "pets", "plants", "diy", "cars", "motorcycles", "home"])
    ]

    private var communityCatalog: [WhisperCommunity] {
        WhisperCommunity.catalog.filter { !$0.requiresJasperLink && $0.id != "dating" }
    }

    private var datingCommunity: WhisperCommunity? {
        WhisperCommunity.catalog.first { $0.id == "dating" }
    }

    private var groupedCommunities: [(title: String, items: [WhisperCommunity])] {
        let catalog = communityCatalog
        var placed = Set<String>()
        var out: [(title: String, items: [WhisperCommunity])] = []
        for section in Self.communitySections {
            let items: [WhisperCommunity] = section.ids.compactMap { id in catalog.first { $0.id == id } }
            items.forEach { placed.insert($0.id) }
            if !items.isEmpty { out.append((section.title, items)) }
        }
        let rest = catalog.filter { !placed.contains($0.id) }
        if !rest.isEmpty { out.append(("More", rest)) }
        return out
    }

    private var communitiesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader("Join your communities", "Each community has its own feed. Pick what you're into — your home feed starts here.")
            if let dating = datingCommunity {
                datingFeatureCard(dating)
            }
            ForEach(groupedCommunities, id: \.title) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(1.0)
                        .foregroundStyle(muted)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(section.items) { community in
                            communityCard(community)
                        }
                    }
                }
            }
            Text(selectedCommunities.isEmpty
                 ? "Join or leave any community later from the Communities tab."
                 : "\(selectedCommunities.count) selected · join or leave any community later from the Communities tab.")
                .font(.caption)
                .foregroundStyle(muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func toggleCommunity(_ id: String) {
        Haptics.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if selectedCommunities.contains(id) { selectedCommunities.remove(id) }
            else { selectedCommunities.insert(id) }
        }
    }

    private func datingFeatureCard(_ community: WhisperCommunity) -> some View {
        let active = selectedCommunities.contains(community.id)
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        return Button {
            toggleCommunity(community.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(colors: community.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 16)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Whisper Dating")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ink)
                        Text("18+")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(rose)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(rose.opacity(0.14), in: Capsule())
                    }
                    Text("Blind video dates, an icebreaker every hour, and real people near you. Private by default — you decide what's shared.")
                        .font(.caption)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                checkCircle(active: active, tint: rose)
                    .padding(.top, 2)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [rose.opacity(0.10), Color(red: 1.0, green: 0.62, blue: 0.72).opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(active ? rose : hairline, lineWidth: active ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func communityCard(_ community: WhisperCommunity) -> some View {
        let active = selectedCommunities.contains(community.id)
        return Button {
            toggleCommunity(community.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: community.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(colors: community.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 12)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(community.name)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(community.tagline)
                        .font(.system(size: 10.5))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                checkCircle(active: active, tint: ink)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBG, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(active ? ink : hairline, lineWidth: active ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func checkCircle(active: Bool, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(active ? tint : Color.clear)
            Circle()
                .strokeBorder(active ? tint : hairline, lineWidth: 1.2)
            if active {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(surfaceBG)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Step 2: People

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Follow people", "Your feed is built from who you follow. Here are some accounts to start with.")
            Button {
                Haptics.tap()
                presentFindFriends = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline.weight(.bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find friends from contacts")
                            .font(.subheadline.weight(.bold))
                        Text("Matched privately — contacts never leave your phone in the clear.")
                            .font(.caption2)
                            .foregroundStyle(surfaceBG.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(surfaceBG)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ink, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if suggestions.isEmpty {
                VStack(spacing: 8) {
                    WhisperMeetDoodle(symbol: "person.3", height: 120)
                    Text("No suggestions yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text("You can find people from Search once the community grows.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                HStack {
                    Text("SUGGESTED FOR YOU")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.0)
                        .foregroundStyle(muted)
                    Spacer()
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3)) {
                            selectedFollows = Set(suggestions.prefix(12).map { $0.user_id })
                        }
                    } label: {
                        Text("Follow all")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.prefix(12))) { user in
                        followRow(user)
                        if user.id != suggestions.prefix(12).last?.id {
                            Divider().background(hairline)
                        }
                    }
                }
                .background(cardBG, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(hairline, lineWidth: 1)
                }
            }
        }
    }

    private func followRow(_ user: WhisperUserRow) -> some View {
        let isFollowing = selectedFollows.contains(user.user_id)
        let name: String = (user.display_name?.isEmpty == false) ? (user.display_name ?? user.username) : user.username
        return HStack(spacing: 12) {
            WhisperAvatar(
                username: user.username,
                size: 44,
                imageURL: user.profile_image_url.flatMap { URL(string: $0) }
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text("@\(user.username)" + ((user.bio ?? "").isEmpty ? "" : " · \(user.bio ?? "")"))
                    .font(.caption)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.3)) {
                    if isFollowing { selectedFollows.remove(user.user_id) }
                    else { selectedFollows.insert(user.user_id) }
                }
            } label: {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isFollowing ? ink : surfaceBG)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(isFollowing ? cardBG : ink, in: .rect(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(hairline, lineWidth: isFollowing ? 1 : 0)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Step 3: Link Jasper

    private var jasperStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Link Jasper", "Jasper is the AI fitness app Whisper partners with. Link your account and Jasper answers with your real workouts, meals, and sleep.")
            OnboardingJasperLinkCard(linked: $jasperLinked)
            Text("Optional — you can link Jasper later from Settings → Jasper.")
                .font(.caption)
                .foregroundStyle(muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Step 4: How Whisper works (guidelines)

    private struct Guideline: Identifiable {
        let id: String
        let icon: String
        let title: String
        let body: String
    }

    private static let guidelines: [Guideline] = [
        Guideline(id: "real", icon: "person.2.fill", title: "Real people, real names",
                  body: "One account per person. Be who you say you are — impersonation and fake accounts are removed."),
        Guideline(id: "zero", icon: "shield.lefthalf.filled", title: "Zero tolerance",
                  body: "No hate, harassment, sexual content, violence, or anything that endangers minors. Accounts that cross these lines are removed without warning."),
        Guideline(id: "control", icon: "eye.fill", title: "You control what people see",
                  body: "Switch to a private account, block or mute anyone, and choose what Jasper data your coaches can see."),
        Guideline(id: "report", icon: "flag.fill", title: "Report anything, right here",
                  body: "Every post, message, profile, and live room has a report option. Reports are reviewed by a real person."),
        Guideline(id: "data", icon: "lock.fill", title: "Your data stays yours",
                  body: "Health data linked from Jasper is never sold or shown publicly. Dating preferences and location are shared only as a rounded distance.")
    ]

    private var guidelinesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader("How Whisper works", "A few things everyone agrees to before joining.")
            ForEach(Self.guidelines) { item in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .background(cardBG, in: Circle())
                        .overlay(Circle().strokeBorder(hairline, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ink)
                        Text(item.body)
                            .font(.footnote)
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Finish

    private func finish() async {
        isSubmitting = true
        blocks.acceptEULA()
        // Community picks ride along as interests — the membership signal
        // both apps read (lowercased community names).
        let pickedNames: [String] = WhisperCommunity.catalog
            .filter { selectedCommunities.contains($0.id) }
            .map { $0.name }
        let interests: [String] = Array(Set(pickedNames.map { $0.lowercased() }))
        let ok = await users.completeOnboarding(bio: bio, interests: interests)
        for uid in selectedFollows {
            if let row = suggestions.first(where: { $0.user_id == uid }) {
                _ = await follows.follow(userID: uid, username: row.username)
            }
        }
        await follows.refresh()
        if !pickedNames.isEmpty {
            UserDefaults.standard.set(pickedNames, forKey: "whisper.onboarding.communities")
        }
        isSubmitting = false
        if ok || users.hasOnboarded {
            Haptics.success()
            celebrationMark = false
            go(to: 5)
        }
    }

    // MARK: - Step 5: Done

    private var doneStep: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 132, height: 132)
                Circle()
                    .strokeBorder(Color.green.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 132, height: 132)
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(.green)
                    .rotationEffect(.degrees(celebrationMark ? 0 : -18))
                WhisperEmberMascot(
                    size: 54,
                    isActive: true,
                    expression: WhisperEmberCoachMode.regular.resolved.signatureExpression,
                    coachMode: WhisperEmberCoachMode.regular.resolved
                )
                .offset(x: 58, y: -58)
            }
            .scaleEffect(celebrationMark ? 1 : 0.35)
            .opacity(celebrationMark ? 1 : 0)
            .padding(.top, 40)

            VStack(spacing: 8) {
                Text("You're all set, \(displayNameDraft.isEmpty ? displayUsername : displayNameDraft).")
                    .font(.title2.weight(.black))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                Text("Your profile is live and your feed is ready.")
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
            }
            .opacity(celebrationMark ? 1 : 0)
            .offset(y: celebrationMark ? 0 : 14)

            VStack(spacing: 0) {
                recapRow(icon: "person.3.fill", text: selectedCommunities.isEmpty
                         ? "Communities are one tap away in the tab bar"
                         : "\(selectedCommunities.count) communit\(selectedCommunities.count == 1 ? "y" : "ies") joined")
                Divider().background(hairline)
                recapRow(icon: "person.crop.circle.badge.checkmark", text: selectedFollows.isEmpty
                         ? "Follow people from Search any time"
                         : "Following \(selectedFollows.count) \(selectedFollows.count == 1 ? "person" : "people")")
                Divider().background(hairline)
                recapRow(icon: "link", text: jasperLinked ? "Jasper linked — your data flows in" : "Link Jasper later in Settings")
            }
            .background(cardBG, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(hairline, lineWidth: 1)
            }
            .opacity(celebrationMark ? 1 : 0)
            .offset(y: celebrationMark ? 0 : 18)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            Haptics.success()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.15)) {
                celebrationMark = true
            }
        }
    }

    private func recapRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WhisperEmberPillPalette.glow)
                .frame(width: 26, height: 26)
                .background(WhisperEmberPillPalette.glow.opacity(0.14), in: Circle())
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - The onboarding Jasper link card

/// The Connect-Jasper journey, sized for onboarding: the same proven logic
/// as `ConnectJasperButton` (mint the token off the linked-or-same Jasper
/// sign-in; hop to Jasper's Allow screen only when the graph is empty; the
/// return deep link + foreground poll finish it) — without the settings-card
/// clutter. States: not linked → connecting → finish in Jasper → linked.
private struct OnboardingJasperLinkCard: View {
    @Binding var linked: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var client = JasperConnectClient.shared
    @State private var link = WhisperWhisperLinkService.shared
    @State private var showJasperPermissions: Bool = false
    @State private var awaitingJasperReturn: Bool = false
    @State private var showLinkFallback: Bool = false
    @State private var showCelebration: Bool = false

    private let jasperOrange = Color(red: 0.953, green: 0.565, blue: 0.341)

    private enum AccountResolution { case linkedAccounts, sameAccount, unlinked }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var cardBG: Color { WhisperTheme.card(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            perksBlock
            Divider().background(hairline)
            stateBlock
                .padding(14)
        }
        .background(cardBG, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(hairline, lineWidth: 1)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: awaitingJasperReturn)
        .fullScreenCover(isPresented: $showCelebration) {
            JasperConnectionCelebration()
        }
        .sheet(isPresented: $showLinkFallback) {
            WhisperConnectWhisperView(startWithCode: true)
                .whisperSheetBorder()
        }
        .sheet(isPresented: $showJasperPermissions) { JasperPermissionsView(onAllow: performConnect) }
        .onChange(of: client.state) { _, _ in syncLinkedFlag() }
        .onChange(of: link.lastLinkedAt) { _, stamp in
            guard stamp != nil, awaitingJasperReturn || showLinkFallback else { return }
            awaitingJasperReturn = false
            showLinkFallback = false
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                showJasperPermissions = true
            }
        }
        .onChange(of: link.lastDeniedAt) { _, denied in
            guard denied != nil, awaitingJasperReturn else { return }
            awaitingJasperReturn = false
            Haptics.warning()
        }
        .onChange(of: scenePhase) { _, phase in
            // Foreground fallback: if Jasper's return link never arrived,
            // poll once — a landed link completes through lastLinkedAt.
            guard phase == .active, awaitingJasperReturn else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                await link.checkPendingReturn()
            }
        }
        .task {
            syncLinkedFlag()
            await client.validate()
            syncLinkedFlag()
        }
    }

    // MARK: Perks

    private var perksBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            JasperAppIcon(size: 48, cornerScale: 0.28)
            VStack(alignment: .leading, spacing: 6) {
                Text(isLinkedNow ? "Jasper is linked" : "What you get")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                perkLine("Jasper answers with your real training, nutrition, and readiness.")
                perkLine("Coaches you hire see only what you choose to share.")
                perkLine("Unlocks the Jasper Circle community.")
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func perkLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(jasperOrange)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: State

    @ViewBuilder
    private var stateBlock: some View {
        if awaitingJasperReturn {
            finishInJasperBlock
        } else {
            switch client.state {
            case .notConnected:
                notLinkedBlock
            case .connecting:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to Jasper…")
                        .font(.subheadline)
                        .foregroundStyle(ink)
                }
                .frame(height: 44)
            case .connected(let info):
                if resolution(info) == .unlinked {
                    unlinkedBlock
                } else {
                    linkedBlock(info)
                }
            case .error(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    primaryButton("Try again", icon: "arrow.clockwise") { startConnect() }
                }
            }
        }
    }

    private var notLinkedBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            primaryButton("Link Jasper", icon: "link") { startConnect() }
            HStack {
                Button {
                    Haptics.tap()
                    showLinkFallback = true
                } label: {
                    Text("Enter a code instead")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                }
                .buttonStyle(.plain)
                Spacer()
                if let url = WhisperWhisperPromoCard.appStoreURL {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("Get Jasper")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(jasperOrange)
                    }
                }
            }
        }
    }

    private var finishInJasperBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish in Jasper")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ink)
                    Text("Tap Allow in Jasper — this completes by itself.")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                pendingPill("Open Jasper again") { _ = link.beginDeepLink() }
                pendingPill("Enter code") {
                    awaitingJasperReturn = false
                    showLinkFallback = true
                }
                Spacer()
                Button {
                    Haptics.tap()
                    awaitingJasperReturn = false
                } label: {
                    Text("Cancel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var unlinkedBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One more step — approve Whisper inside Jasper so your real data flows in.")
                .font(.caption)
                .foregroundStyle(jasperOrange)
                .fixedSize(horizontal: false, vertical: true)
            primaryButton("Finish in Jasper", icon: "arrow.up.forward.app.fill") {
                if link.beginDeepLink() {
                    awaitingJasperReturn = true
                } else {
                    showLinkFallback = true
                }
            }
        }
    }

    private func linkedBlock(_ info: JasperConnection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.green, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                Text(info.username.map { "@\($0) · your Jasper data now flows into Whisper" }
                     ?? "Your Jasper data now flows into Whisper")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                Haptics.tap()
                showCelebration = true
            } label: {
                Text("View")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(jasperOrange)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(jasperOrange.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                LinearGradient(colors: [jasperOrange, Color(red: 0.98, green: 0.45, blue: 0.09)], startPoint: .leading, endPoint: .trailing),
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    private func pendingPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(jasperOrange)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(jasperOrange.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Logic (mirrors ConnectJasperButton.startConnect)

    private func startConnect() { showJasperPermissions = true }

    private func performConnect(scopes: [String]) {
        let generation = AccountStorage.generation
        Task {
            await client.connect(scopes: scopes)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            switch client.state {
            case .connected(let info):
                if resolution(info) == .unlinked {
                    if link.beginDeepLink() {
                        awaitingJasperReturn = true
                    } else {
                        showLinkFallback = true
                    }
                } else {
                    syncLinkedFlag()
                    Haptics.success()
                    showCelebration = true
                }
            case .error:
                Haptics.warning()
            default:
                break
            }
        }
    }

    private var isLinkedNow: Bool {
        if case .connected(let info) = client.state { return resolution(info) != .unlinked }
        return false
    }

    private func syncLinkedFlag() {
        let now = isLinkedNow
        if linked != now { linked = now }
    }

    /// `linked:true` = an account link resolved a different owner; a username
    /// with `linked:false` = the same sign-in owns a Jasper profile; neither =
    /// unlinked (empty graph). nil metadata falls back to the link service.
    private func resolution(_ info: JasperConnection) -> AccountResolution {
        if info.linked == true { return .linkedAccounts }
        if info.username != nil { return .sameAccount }
        if info.linked == false { return .unlinked }
        return link.isLinked ? .linkedAccounts : .unlinked
    }
}

// MARK: - Flow layout for chip wrapping

/// Lightweight flowing layout that wraps chips onto the next line.
struct WhisperFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Confetti burst

/// One-shot confetti rain for the onboarding finale — deterministic
/// particles drawn in a Canvas; nothing keeps running once the burst
/// finishes (~3.5s).
struct WhisperConfettiBurst: View {
    @State private var startedAt = Date()

    private struct Piece {
        let x: CGFloat
        let delay: Double
        let fall: Double
        let size: CGFloat
        let colorIndex: Int
        let spin: Double
        let sway: CGFloat
    }

    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.83, blue: 0.60),
        Color(red: 0.49, green: 0.92, blue: 0.77),
        .orange, .pink, .yellow, .cyan,
        Color(red: 0.63, green: 0.56, blue: 1.0)
    ]

    private static let pieces: [Piece] = (0..<54).map { i in
        let f = Double(i)
        let r1 = abs((sin(f * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1))
        let r2 = abs(sin(f * 78.233) * 0.5 + 0.5)
        let r3 = abs(cos(f * 3.7) * 0.5 + 0.5)
        let r4 = abs(sin(f * 5.1) * 0.5 + 0.5)
        let r5 = abs(cos(f * 9.3) * 0.5 + 0.5)
        return Piece(
            x: CGFloat(r1),
            delay: r2 * 0.9,
            fall: 0.75 + r3 * 0.6,
            size: 6 + CGFloat(r4 * 6),
            colorIndex: i % 7,
            spin: 2.2 + r5 * 4.4,
            sway: CGFloat(f)
        )
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startedAt)
                guard t < 3.6 else { return }
                for piece in Self.pieces {
                    let life = t - piece.delay
                    guard life > 0 else { continue }
                    let progress = life / (2.1 / piece.fall)
                    guard progress < 1 else { continue }
                    let y = -30 + CGFloat(progress) * (size.height * 0.92 + 60)
                    let x = piece.x * size.width + sin(CGFloat(life) * 2.6 + piece.sway) * 22
                    var inner = context
                    inner.opacity = progress > 0.72 ? max(0, (1 - progress) / 0.28) : 1
                    inner.translateBy(x: x, y: y)
                    inner.rotate(by: .radians(life * piece.spin))
                    let rect = CGRect(
                        x: -piece.size / 2,
                        y: -piece.size * 0.3,
                        width: piece.size,
                        height: piece.size * 0.6
                    )
                    inner.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(Self.palette[piece.colorIndex % Self.palette.count])
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
