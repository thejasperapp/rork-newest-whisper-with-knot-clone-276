import SwiftUI
import Supabase

/// Whisper's hamburger menu — Instagram-style settings list, pure B&W.
/// Whisper is its own app, so this menu is intentionally separate from
/// Whisper's `SettingsView`. Account-level actions (sign out) still hit
/// the shared `AuthenticationService` because the two apps share login.
struct WhisperSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    /// Optional callback invoked when the user taps "Saved posts" so the
    /// presenting screen can swap from this settings sheet over to a
    /// dedicated saved-posts sheet without nesting modals.
    var onOpenSaved: (() -> Void)? = nil
    /// BACK-SHEET MODE — when the profile mounts this menu as the layer
    /// BEHIND its card (the swipe-to-reveal grammar), closing means sliding
    /// the profile card back over it, not dismissing a modal. The profile
    /// passes that slide here; every Close/back path in this menu routes
    /// through `close()` so it works in both presentations.
    var onClose: (() -> Void)? = nil
    var onRootChanged: (Bool) -> Void = { _ in }

    /// Closes the menu — the back-sheet slide when embedded, `dismiss()` when
    /// presented as a sheet.
    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    @State private var auth = AuthenticationService.shared
    @State private var requests = FriendRequestsService.shared
    @State private var followRequests = WhisperFollowRequestService.shared
    @State private var users = WhisperUserService.shared
    @State private var coach = WhisperCoachService.shared
    @State private var coachRequests = WhisperCoachRequestService.shared
    @State private var verification = WhisperVerificationService.shared

    @State private var activeSheet: ActiveSheet?
    @State private var reportsService = WhisperReportsService.shared
    @State private var phoneService = WhisperPhoneService.shared
    @State private var jasperLink = WhisperWhisperLinkService.shared

    @State private var pushNotifications: Bool = WhisperNotificationPrefs.masterEnabled
    @State private var quietMode: Bool = AccountStorage.bool(forKey: "whisper.quiet")
    /// Live settings search — filters every row by title/keywords, like
    /// Instagram's "Settings and activity" search field.
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool
    /// Programmatic navigation path so search results can push the same
    /// destinations the section rows navigate to.
    @State private var path: NavigationPath = NavigationPath()
    /// Branded confirmation sheet (log out).
    @State private var actionMenu: WhisperActionMenuModel?
    /// Drives the one-shot entrance animation.
    @State private var appeared: Bool = false
    @State private var privateAccount: Bool = (WhisperUserService.shared.me?.is_private ?? AccountStorage.bool(forKey: "whisper.private"))
    @State private var savingPrivacy: Bool = false
    @State private var privacyError: String? = nil
    @State private var signOutError: String?
    @State private var isSigningOutEverywhere: Bool = false
    @State private var showClearMessages = false
    @State private var clearingMessages = false
    @State private var messagesCleared = false
    @State private var messagesClearFailed = false

    private struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let action: () -> Void
        var trailing: String? = nil
    }

    /// Every modal this screen can present, funneled through a single
    /// `.sheet(item:)`. Stacking ~18 separate `.sheet(isPresented:)` modifiers
    /// on one view is a SwiftUI footgun: it works in the debug simulator but
    /// hard-crashes on launch in release/TestFlight builds. One enum-driven
    /// sheet keeps presentation to a single modifier. The approval
    /// celebration sheets (coach / verified welcome) ALSO live here — a
    /// second `.sheet(item: $celebration)` on the same view was the real
    /// root cause of the hamburger-menu release crash, because the inbox
    /// (alive in the TabView) and this sheet could both try to present at
    /// the same instant during a status refresh.
    private enum ActiveSheet: Int, Identifiable {
        case coachAccess, editProfile, phone, findFriends, about
        case coachApply, verifyApply
        case accountApps, reportsDashboard, myCoaches
        case whisperOne, jasperPromo, coachRate, mySubscriptions, myArticles, safetyInfo
        case badgeActivateCoach, badgeActivateVerified
        case creatorLink
        case celebrateCoach, celebrateVerified
        case reportProblem
        case analytics, savedPosts, decisions
        var id: Int { rawValue }

        /// Destinations that read as real *pages* (workspaces, applications,
        /// dashboards) present edge-to-edge via `fullScreenCover`; only quick
        /// utility actions stay as swipe-away sheets.
        var isFullPage: Bool {
            switch self {
            case .editProfile, .findFriends, .coachApply,
                 .verifyApply, .accountApps,
                 .reportsDashboard, .myCoaches, .mySubscriptions,
                 .myArticles, .safetyInfo, .about, .analytics, .savedPosts, .decisions:
                return true
            default:
                return false
            }
        }
    }

    /// `activeSheet` filtered down to half-sheet destinations.
    private var halfSheetBinding: Binding<ActiveSheet?> {
        Binding(
            get: { (activeSheet?.isFullPage == false) ? activeSheet : nil },
            set: { newValue in
                if newValue == nil, activeSheet?.isFullPage == false { activeSheet = nil }
            }
        )
    }

    /// `activeSheet` filtered down to full-page destinations.
    private var fullPageBinding: Binding<ActiveSheet?> {
        Binding(
            get: { (activeSheet?.isFullPage == true) ? activeSheet : nil },
            set: { newValue in
                if newValue == nil, activeSheet?.isFullPage == true { activeSheet = nil }
            }
        )
    }

    /// Studios and dashboards — real workspaces, so they present as full
    /// screens (fullScreenCover) instead of swipe-away sheets. Each view
    /// carries its own NavigationStack and Close button.
    private enum ActiveStudio: Int, Identifiable {
        case coachStudio, coachClients, creatorPayouts, coachEarnings
        var id: Int { rawValue }
    }
    @State private var activeStudio: ActiveStudio?

    /// Pushed (non-modal) destinations. Value-based navigation keeps the
    /// destination views LAZY — `NavigationLink { Destination() }` builds the
    /// destination struct (and runs all of its `@State`/service initializers)
    /// on every body evaluation, which is exactly what crashed the hamburger
    /// menu the moment the sheet appeared. With `NavigationLink(value:)` the
    /// destination is only created when the user actually navigates.
    private enum SettingsRoute: Int, Hashable {
        case securityCenter, notificationSettings, blockedAccounts, mutedWords, followRequests, yourActivity
    }

    /// The signed-in handle the account-access matrix keys on.
    private var accessUsername: String {
        users.me?.username ?? auth.currentUser.username ?? ""
    }

    /// The highest-priority approval celebration waiting to be shown, or
    /// nil when none is pending. Drives the inline banner — the user taps it
    /// to present the welcome. We NEVER auto-present from here, because the
    /// inbox (alive in the TabView) could race this sheet's own presentation
    /// and crash UIKit on release builds. The banner is tap-to-present and
    /// safe.
    private var pendingCelebration: ActiveSheet? {
        if coach.shouldCelebrateApproval { return .celebrateCoach }
        if verification.shouldCelebrateApproval { return .celebrateVerified }
        return nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        searchBar
                        if isSearching {
                            searchResultsSection
                        } else {
                        accountHeader

                        if let pending = pendingCelebration, activeSheet == nil {
                            celebrationBanner(pending)
                        }

                        section(title: "Your account") {
                            row(icon: "person.crop.circle", title: "Edit profile") {
                                Haptics.tap()
                                activeSheet = .editProfile
                            }
                            divider
                            phoneSettingsRow
                            divider
                            row(icon: "bookmark", title: "Saved posts") {
                                Haptics.tap()
                                if let onOpenSaved {
                                    onOpenSaved()
                                } else {
                                    activeSheet = .savedPosts
                                }
                            }
                            divider
                            row(icon: "lock", title: "Private account", toggle: Binding(get: { privateAccount }, set: { requested in
                                guard !savingPrivacy else { return }
                                savingPrivacy = true
                                privacyError = nil
                                let generation = AccountStorage.generation
                                Task {
                                    let saved = await users.setIsPrivate(requested)
                                    guard generation == AccountStorage.generation else { return }
                                    savingPrivacy = false
                                    if saved {
                                        privateAccount = requested
                                        AccountStorage.set(requested, forKey: "whisper.private")
                                    } else {
                                        privacyError = "Privacy wasn’t updated. Please try again."
                                    }
                                }
                            }))
                            .disabled(savingPrivacy)
                            if savingPrivacy { ProgressView("Updating privacy…").font(.footnote).padding(.horizontal, 14) }
                            if let privacyError { Text(privacyError).font(.footnote).foregroundStyle(.red).padding(.horizontal, 14).accessibilityAddTraits(.updatesFrequently) }
                            if privateAccount {
                                divider
                                NavigationLink(value: SettingsRoute.followRequests) {
                                    followRequestsNavRow
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // IG-style regroup — quiet uppercase kickers organize the
                        // page exactly like the web settings (round-68 grammar).
                        groupKicker("How you use Whisper")

                        section(title: "Your activity") {
                            NavigationLink(value: SettingsRoute.yourActivity) {
                                HStack(spacing: 12) {
                                    iconTile("chart.bar.doc.horizontal", tint: WhisperBrandGradient.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Your activity")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        Text("Interactions, what you've shared, time spent, account history")
                                            .font(.caption)
                                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if let posts = activityPostsCount {
                                        Text("\(posts) posts")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        .task { await loadActivityCounts() }

                        // ANALYTICS — the professional tier's insights door. Shown for
                        // self-selected creator/business accounts and Whisper One
                        // members; verified creators get Creator Studio below instead.
                        if WhisperAccountAccess.canOpenAnalytics(username: accessUsername) {
                            section(title: "Analytics") {
                                analyticsRow
                            }
                        }

                        groupKicker("Account security")

                        section(title: "Security") {
                            NavigationLink(value: SettingsRoute.securityCenter) {
                                navRow(icon: "lock.shield", title: "Security & login")
                            }
                            .buttonStyle(.plain)
                            divider
                            whereLoggedInRow
                            divider
                            destructiveRow(title: "Sign out of all devices") {
                                Haptics.tap()
                                presentGlobalSignOutConfirm()
                            }
                        }

                        groupKicker("Payments & memberships")

                        section(title: "Membership") {
                            whisperOneRow
                        }

                        coachSection
                        verificationSection

                        coachPaymentsSection

                        groupKicker("More from Whisper")

                        section(title: "Grow Whisper") {
                            row(icon: "link.badge.plus", title: "Creator link & invite code") {
                                Haptics.tap()
                                activeSheet = .creatorLink
                            }
                        }

                        section(title: "Discover") {
                            row(icon: "person.2.fill", title: "Find friends from contacts") {
                                Haptics.tap()
                                activeSheet = .findFriends
                            }
                            divider
                            discoverableByPhoneRow
                            if let error = phoneService.lastError {
                                Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 14)
                                Button("Retry phone settings") {
                                    Task {
                                        guard await phoneService.hydrate(force: true) else { return }
                                        await phoneService.setDiscoverable(phoneService.discoverable)
                                    }
                                }.frame(minHeight: 44).disabled(phoneService.isSaving)
                            }
                        }

                        section(title: "Sync with Jasper") {
                            // ONE button runs the whole journey (account link +
                            // Connect token): tap → approve in Jasper if needed →
                            // auto-return → celebration walkthrough.
                            ConnectJasperButton()
                            divider
                            row(icon: "figure.strengthtraining.traditional", title: "Coach access") {
                                Haptics.tap()
                                activeSheet = .coachAccess
                            }
                        }

                        section(title: "Also from Whisper") {
                            Button {
                                Haptics.tap()
                                activeSheet = .jasperPromo
                            } label: {
                                WhisperWhisperPromoCard()
                                    .padding(.horizontal, -2)
                                    .padding(.top, 2)
                            }
                            .buttonStyle(.plain)
                            divider
                            row(icon: "safari", title: "thejasperapp.com") {
                                Haptics.tap()
                                if let url = URL(string: "https://www.thejasperapp.com") { WhisperInAppBrowser.shared.open(url) }
                            }
                        }

                        groupKicker("How others can interact with you")

                        section(title: "Notifications") {
                            NavigationLink(value: SettingsRoute.notificationSettings) {
                                navRow(icon: "bell", title: "Notifications")
                            }
                            .buttonStyle(.plain)
                            divider
                            row(icon: "moon", title: "Quiet mode", toggle: Binding(get: { quietMode }, set: { value in
                                quietMode = value
                                WhisperNotificationPrefs.quietMode = value
                            }))
                        }

                        section(title: "Safety") {
                            row(icon: "text.bubble", title: "Decisions & appeals") {
                                Haptics.tap()
                                activeSheet = .decisions
                            }
                            divider
                            row(icon: "shield.checkered", title: "Safety on Whisper") {
                                Haptics.tap()
                                activeSheet = .safetyInfo
                            }
                            divider
                            NavigationLink(value: SettingsRoute.blockedAccounts) {
                                navRow(icon: "person.crop.circle.badge.xmark", title: "Blocked accounts")
                            }
                            .buttonStyle(.plain)
                            divider
                            NavigationLink(value: SettingsRoute.mutedWords) {
                                navRow(icon: "text.badge.minus", title: "Muted words")
                            }
                            .buttonStyle(.plain)
                            divider
                            row(icon: "flag", title: "Report a problem") {
                                Haptics.tap()
                                // In-app report — never an email hand-off.
                                activeSheet = .reportProblem
                            }
                        }

                        groupKicker("More info & support")

                        section(title: "About") {
                            row(icon: "info.circle", title: "About Whisper") {
                                Haptics.tap()
                                activeSheet = .about
                            }
                            divider
                            row(icon: "hand.raised", title: "Privacy policy") {
                                Haptics.tap()
                                if let url = URL(string: "https://www.mydailywhisper.com/privacy") { WhisperInAppBrowser.shared.open(url) }
                            }
                            divider
                            row(icon: "doc.text", title: "Terms of service") {
                                Haptics.tap()
                                if let url = URL(string: "https://www.mydailywhisper.com/terms") { WhisperInAppBrowser.shared.open(url) }
                            }
                            divider
                            row(icon: "globe", title: "mydailywhisper.com") {
                                Haptics.tap()
                                if let url = URL(string: "https://www.mydailywhisper.com") { WhisperInAppBrowser.shared.open(url) }
                            }
                        }

                        groupKicker("Storage")
                        section(title: nil) {
                            row(icon: "internaldrive", title: messagesClearFailed ? "Couldn’t clear messages · Retry" : (messagesCleared ? "Cached messages cleared" : "Clear cached messages")) {
                                Haptics.tap()
                                showClearMessages = true
                            }
                            .disabled(clearingMessages)
                            Text("Remove saved text from this device. Your chat history and unsent messages stay safe. Open chats can save a new copy after their next refresh.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.bottom, 14)
                        }

                        groupKicker("Login & account")

                        section(title: nil) {
                            destructiveRow(title: "Log out") {
                                Haptics.tap()
                                presentLogoutConfirm()
                            }
                        }

                        brandFooter
                        } // end !isSearching
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    // Embedded settings are already revealed by the moving
                    // profile. A second fade/slide makes the first open stutter.
                    .opacity(onClose != nil || appeared ? 1 : 0)
                    .offset(y: onClose != nil || appeared ? 0 : 14)
                }
            }
            .onAppear {
                if onClose == nil {
                    withAnimation(.whisperGentle) { appeared = true }
                } else {
                    appeared = true
                }
            }
            .animation(.whisperSmooth, value: isSearching)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        close()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            if onClose != nil {
                                Text("Profile")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .accessibilityLabel(onClose == nil ? "Close settings" : "Back to profile")
                }
            }
            .whisperEdgeBack(isEnabled: onClose == nil && path.isEmpty) { close() }
            .onChange(of: path.count) { _, _ in
                onRootChanged(path.isEmpty)
                if path.isEmpty { quietMode = WhisperNotificationPrefs.quietMode }
            }
            .onAppear { onRootChanged(path.isEmpty) }
            .navigationDestination(for: SettingsRoute.self) { route in
                Group { switch route {
                case .securityCenter: WhisperSecurityCenterView()
                case .notificationSettings: WhisperNotificationSettingsView()
                case .blockedAccounts: WhisperBlockedAccountsView()
                case .mutedWords: WhisperMutedWordsView()
                case .followRequests: WhisperFollowRequestsView()
                case .yourActivity: WhisperYourActivityView()
                } }.whisperNavigationBack()
            }
            .whisperActionMenu($actionMenu)
            .sheet(item: halfSheetBinding) { sheet in
                sheetView(for: sheet)
            }
            .fullScreenCover(item: fullPageBinding) { sheet in
                sheetView(for: sheet)
            }
            .fullScreenCover(item: $activeStudio) { studio in
                studioView(for: studio)
            }
            .task(id: AccountStorage.generation) {
                let generation = AccountStorage.generation
                async let jasper: Bool = jasperLink.refreshStatus()
                async let phone = phoneService.hydrate()
                async let requests: Void = followRequests.refresh()
                async let coachStatus: Void = coach.refreshMyStatus()
                async let coachingRequests: Void = coachRequests.refresh()
                async let verificationStatus: Void = verification.refreshMyStatus()
                await users.refreshMeIfStale()
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                // Reconcile the local toggle with the server's authoritative value
                // so a user signing in on a new device sees their saved choice.
                if let serverPrivate = users.me?.is_private {
                    privateAccount = serverPrivate
                }
                _ = await (jasper, phone, requests, coachStatus, coachingRequests, verificationStatus)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                let me = LeaderboardService.shared.savedUsername
                    ?? AuthenticationService.shared.currentUser.username
                    ?? ""
                if !me.isEmpty {
                    await UserVerificationService.shared.preload(usernames: [me])
                }
            }
            .whisperRefreshable {
                await coach.refreshMyStatus()
                await coachRequests.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await coach.refreshMyStatus() }
                }
            }
.onChange(of: pushNotifications) { _, v in WhisperNotificationPrefs.masterEnabled = v }
            .confirmationDialog("Clear cached messages?", isPresented: $showClearMessages, titleVisibility: .visible) {
                Button("Clear cached messages", role: .destructive) {
                    clearingMessages = true
                    let generation = AccountStorage.generation
                    Task {
                        let cleared = await WhisperMessageCache.clearCurrent()
                        guard generation == AccountStorage.generation else { return }
                        clearingMessages = false
                        messagesCleared = cleared
                        messagesClearFailed = !cleared
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only saved text on this device is removed. Messages on Whisper and pending sends are not deleted.")
            }
            .alert("Couldn’t sign out everywhere", isPresented: Binding(get: { signOutError != nil }, set: { if !$0 { signOutError = nil } })) {
                Button("OK", role: .cancel) { signOutError = nil }
            } message: { Text(signOutError ?? "Please try again.") }
        }
    }

    // MARK: - Phone

    /// Tappable row that opens the phone sheet. Shows the user's saved
    /// number (or a CTA when none is set) so existing accounts can backfill.
    private var phoneSettingsRow: some View {
        Button {
            Haptics.tap()
            activeSheet = .phone
        } label: {
            HStack(spacing: 12) {
                iconTile("phone")
                VStack(alignment: .leading, spacing: 2) {
                    Text(phoneService.phone == nil ? "Add phone number" : "Phone number")
                        .font(.body)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    if let p = phoneService.phone {
                        Text(WhisperPhoneService.displayFormatted(p))
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    } else {
                        Text("Help friends find you on Whisper")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Toggle that controls whether other users can match this account by
    /// hashed phone in Find Friends. When flipped off, all identity rows for
    /// this user are wiped from `whisper_contact_identities`.
    private var discoverableByPhoneRow: some View {
        HStack(spacing: 12) {
            iconTile("magnifyingglass.circle")
            VStack(alignment: .leading, spacing: 2) {
                Text("Find me from contacts")
                    .font(.body)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Let people with your phone number or email find you here.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Toggle("Find me from contacts", isOn: Binding(
                get: { phoneService.discoverable },
                set: { newValue in
                    Haptics.tap()
                    Task { await phoneService.setDiscoverable(newValue) }
                }
            ))
            .disabled(phoneService.isSaving)
            .labelsHidden()
            .tint(WhisperTheme.ink(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Coach section

    @ViewBuilder
    private var coachSection: some View {
        if coach.isMeCoach {
            let pending = coachRequests.incoming.filter { $0.status == "pending" }.count
            section(title: "Coach") {
                clientsRow(pending: pending)
            }
            myCoachesSection
        } else {
            myCoachesSection
        }
        if coach.hasApprovedApplication && !coach.isMeCoach {
            section(title: "Coach") {
                Button {
                    Haptics.tap()
                    activeSheet = .badgeActivateCoach
                } label: {
                    HStack(spacing: 12) {
                        iconTile("checkmark.seal.fill", tint: WhisperTheme.coachAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You're approved — activate your tools")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text("\(WhisperBadgeRole.coach.priceText)/year · approved coaching tools")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } else if coach.hasPendingApplication && !coach.isMeCoach {
            section(title: "Coach") {
                HStack(spacing: 12) {
                    iconTile("hourglass", tint: WhisperTheme.coachAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Application under review")
                            .font(.body)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("We'll email you when you're approved.")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        Task { await coach.refreshMyStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(8)
                            .background(WhisperTheme.surface(colorScheme), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        } else if !coach.isMeCoach {
            section(title: "Coach") {
                Button {
                    Haptics.tap()
                    activeSheet = .coachApply
                } label: {
                    HStack(spacing: 12) {
                        WhisperCoachBadge(size: 20)
                            .frame(width: 32, height: 32)
                            .background(WhisperTheme.coachAccent.opacity(colorScheme == .dark ? 0.16 : 0.08), in: .rect(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Become a coach")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text("Verified badge · build programs · send to clients")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var myCoachesSection: some View {
        if !coachRequests.outgoing.isEmpty {
            let active = coachRequests.myCoaches.count
            let pending = coachRequests.outgoing.filter { $0.status == "pending" }.count
            section(title: "My coaches") {
                Button {
                    Haptics.tap()
                    activeSheet = .myCoaches
                } label: {
                    HStack(spacing: 12) {
                        iconTile("person.crop.circle.badge.checkmark", tint: WhisperTheme.coachAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(active > 0 ? "\(active) active coach\(active == 1 ? "" : "es")" : "Manage requests")
                                .font(.body)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            if pending > 0 {
                                Text("\(pending) pending")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func clientsRow(pending: Int) -> some View {
        Button {
            Haptics.tap()
            activeStudio = .coachClients
        } label: {
            HStack(spacing: 12) {
                WhisperCoachBadge(size: 20)
                    .frame(width: 32, height: 32)
                    .background(WhisperTheme.coachAccent.opacity(colorScheme == .dark ? 0.16 : 0.08), in: .rect(cornerRadius: 9))
                Text("Coach Studio")
                    .font(.body)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                if pending > 0 {
                    Text("\(pending)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(WhisperTheme.coachAccent, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Coach payments section

    /// True for anyone who can receive payouts: coaches and verified
    /// creators (sponsorship payouts), plus team roles.
    private var isPayoutEligible: Bool {
        coach.isMeCoach
            || myBadge == .verified || myBadge == .moderator
            || myBadge == .admin || myBadge == .owner
    }

    /// Payments: earnings dashboard + in-app bank linking for every payout-
    /// eligible role (coaches, creators), coach rate setting, and
    /// client-side subscription management.
    @ViewBuilder
    private var coachPaymentsSection: some View {
        if isPayoutEligible {
            section(title: "Payments") {
                row(icon: "banknote", title: "Earnings & payouts") {
                    Haptics.tap()
                    activeStudio = .coachEarnings
                }
                divider
                row(icon: "building.columns", title: "Link bank account") {
                    Haptics.tap()
                    activeStudio = .coachEarnings
                }
                if coach.isMeCoach {
                    divider
                    row(icon: "tag", title: "Set monthly rate") {
                        Haptics.tap()
                        activeSheet = .coachRate
                    }
                }
                if myBadge == .verified || myBadge == .moderator || myBadge == .admin || myBadge == .owner {
                    divider
                    row(icon: "sparkles", title: "Creator payouts (WPP)") {
                        Haptics.tap()
                        activeStudio = .creatorPayouts
                    }
                }
            }
        }
        section(title: "Coaching subscriptions") {
                row(icon: "creditcard", title: "Manage subscriptions") {
                    Haptics.tap()
                    activeSheet = .mySubscriptions
                }
        }
    }

    // MARK: - Verification section

    private var myBadge: UserBadge {
        let me = LeaderboardService.shared.savedUsername
            ?? auth.currentUser.username
            ?? ""
        return UserVerificationService.shared.badge(forUsername: me)
    }

    private var canReviewVerifications: Bool {
        let b = myBadge
        return b == .moderator || b == .admin || b == .owner
    }

    @ViewBuilder
    private var verificationSection: some View {
        section(title: "Verification") {
            if myBadge == .verified || myBadge == .moderator || myBadge == .admin || myBadge == .owner {
                verifiedStatusRow
            } else if verification.hasPendingApplication {
                pendingVerificationRow
            } else {
                applyVerificationRow
            }
            if canReviewVerifications {
                divider
                reviewAccountAppsRow
                divider
                reviewReportsRow
            }
        }
    }

    private var verifiedStatusRow: some View {
        HStack(spacing: 12) {
            iconTile("checkmark.seal.fill", tint: Color(red: 0.13, green: 0.55, blue: 0.96))
            VStack(alignment: .leading, spacing: 2) {
                Text("You're verified")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Algorithm boost, priority push, trending nudge.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var pendingVerificationRow: some View {
        HStack(spacing: 12) {
            iconTile("hourglass", tint: Color(red: 0.13, green: 0.55, blue: 0.96))
            VStack(alignment: .leading, spacing: 2) {
                Text("Application under review")
                    .font(.body)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("We'll notify you when it's decided.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Button {
                Haptics.tap()
                activeSheet = .verifyApply
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .onTapGesture { Haptics.tap(); activeSheet = .verifyApply }
    }

    private var applyVerificationRow: some View {
        Button {
            Haptics.tap()
            activeSheet = .verifyApply
        } label: {
            HStack(spacing: 12) {
                iconTile("checkmark.seal", tint: Color(red: 0.13, green: 0.55, blue: 0.96))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apply for verification")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Blue check · algorithm boost · priority push")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The professional-tier insights door (never Creator Studio).
    private var analyticsRow: some View {
        Button {
            Haptics.tap()
            activeSheet = .analytics
        } label: {
            HStack(spacing: 12) {
                iconTile("chart.bar.xaxis", tint: WhisperBrandGradient.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analytics")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Reach, interactions, followers, top posts")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var reviewReportsRow: some View {
        Button {
            Haptics.tap()
            activeSheet = .reportsDashboard
            Task { await reportsService.loadDashboard() }
        } label: {
            HStack(spacing: 12) {
                iconTile("flag")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review reports")
                        .font(.body)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Mark helpful · dismiss · action")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                if !reportsService.open.isEmpty {
                    Text("\(reportsService.open.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var reviewAccountAppsRow: some View {
        Button {
            Haptics.tap()
            activeSheet = .accountApps
            Task {
                await WhisperAccountApplicationsService.shared.loadDashboard()
                await verification.loadDashboard()
            }
        } label: {
            HStack(spacing: 12) {
                iconTile("figure.run.circle")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account reviews")
                        .font(.body)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Coach · Creator badge")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                let pending = WhisperAccountApplicationsService.shared.pendingCount + verification.pending.count
                if pending > 0 {
                    Text("\(pending)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color(red: 0.92, green: 0.27, blue: 0.20), in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search settings", text: $searchQuery)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .tint(WhisperTheme.ink(colorScheme))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if isSearching {
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) {
                        searchQuery = ""
                        searchFocused = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    searchFocused ? WhisperTheme.ink(colorScheme).opacity(0.35) : WhisperTheme.hairline(colorScheme),
                    lineWidth: searchFocused ? 1 : 0.75
                )
        }
    }

    /// One searchable settings destination.
    private struct SearchEntry: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let group: String
        var keywords: String = ""
        let action: () -> Void
    }

    /// Every navigable row in the menu, flattened for search. Toggles are
    /// intentionally omitted — search is for finding *places*.
    private var searchEntries: [SearchEntry] {
        var out: [SearchEntry] = [
            SearchEntry(icon: "person.crop.circle", title: "Edit profile", group: "Your account", keywords: "name bio avatar photo") { activeSheet = .editProfile },
            SearchEntry(icon: "phone", title: "Phone number", group: "Your account", keywords: "sms contact") { activeSheet = .phone },
            SearchEntry(icon: "bookmark", title: "Saved posts", group: "Your account", keywords: "bookmarks collection") {
                if let onOpenSaved { onOpenSaved() } else { activeSheet = .savedPosts }
            },
            SearchEntry(icon: "lock.shield", title: "Security & login", group: "Security", keywords: "password 2fa two factor face id pin sessions") { path.append(SettingsRoute.securityCenter) },
            SearchEntry(icon: "bell", title: "Notifications", group: "Notifications", keywords: "push alerts") { path.append(SettingsRoute.notificationSettings) },
            SearchEntry(icon: "person.crop.circle.badge.questionmark", title: "Follow requests", group: "Your account", keywords: "private approve") { path.append(SettingsRoute.followRequests) },
            SearchEntry(icon: "checkmark.seal", title: "Verification", group: "Verification", keywords: "blue check verified badge") { activeSheet = .verifyApply },
            SearchEntry(icon: "chart.bar.doc.horizontal", title: "Your activity", group: "Your activity", keywords: "export data likes comments history") { path.append(SettingsRoute.yourActivity) },
            SearchEntry(icon: "creditcard", title: "Coaching subscriptions", group: "Payments", keywords: "cancel billing manage") { activeSheet = .mySubscriptions },
            SearchEntry(icon: "flag", title: "Report a problem", group: "Safety", keywords: "help support") { activeSheet = .reportProblem },
            SearchEntry(icon: "plus.circle", title: "Whisper One", group: "Membership", keywords: "subscription premium upgrade perks") { activeSheet = .whisperOne },
            SearchEntry(icon: "link.badge.plus", title: "Creator link & invite code", group: "Grow Whisper", keywords: "referral invite share") { activeSheet = .creatorLink },
            SearchEntry(icon: "person.2.fill", title: "Find friends from contacts", group: "Discover", keywords: "contacts sync people") { activeSheet = .findFriends },
            SearchEntry(icon: "figure.strengthtraining.traditional", title: "Coach access", group: "Sync with Jasper", keywords: "trainer") { activeSheet = .coachAccess },
            SearchEntry(icon: "text.bubble", title: "Decisions & appeals", group: "Safety", keywords: "correction appeal contact permissions") { activeSheet = .decisions },
            SearchEntry(icon: "shield.checkered", title: "Safety on Whisper", group: "Safety", keywords: "teen guidelines wellbeing") { activeSheet = .safetyInfo },
            SearchEntry(icon: "person.crop.circle.badge.xmark", title: "Blocked accounts", group: "Safety", keywords: "block unblock") { path.append(SettingsRoute.blockedAccounts) },
            SearchEntry(icon: "text.badge.minus", title: "Muted words", group: "Safety", keywords: "filter hide comments") { path.append(SettingsRoute.mutedWords) },
            SearchEntry(icon: "info.circle", title: "About Whisper", group: "About", keywords: "version app") { activeSheet = .about },
            SearchEntry(icon: "circle.lefthalf.filled", title: "Pitch black", group: "Appearance", keywords: "dark mode theme oled black") { searchQuery = "" },
            SearchEntry(icon: "figure.run", title: "Get Jasper", group: "Also from Whisper", keywords: "app store download fitness jasper") {
                activeSheet = .jasperPromo
            },
        ]
        if isPayoutEligible {
            out.append(SearchEntry(icon: "banknote", title: "Earnings & payouts", group: "Payments", keywords: "money bank income") { activeStudio = .coachEarnings })
        }
        if coach.isMeCoach {
            out.append(SearchEntry(icon: "figure.run", title: "Coach Studio", group: "Coach", keywords: "clients programs") { activeStudio = .coachClients })
            out.append(SearchEntry(icon: "tag", title: "Set monthly rate", group: "Payments", keywords: "price coaching") { activeSheet = .coachRate })
        } else {
            out.append(SearchEntry(icon: "checkmark.seal", title: "Become a coach", group: "Coach", keywords: "apply trainer") { activeSheet = .coachApply })
        }
        if !coachRequests.outgoing.isEmpty {
            out.append(SearchEntry(icon: "person.crop.circle.badge.checkmark", title: "My coaches", group: "Coach", keywords: "requests") { activeSheet = .myCoaches })
        }
        return out
    }

    private var searchResults: [SearchEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return searchEntries.filter {
            $0.title.lowercased().contains(q)
                || $0.keywords.lowercased().contains(q)
                || $0.group.lowercased().contains(q)
        }
    }

    /// Flat result list rendered while the user is typing in the search
    /// field — mirrors Instagram's settings search behaviour.
    private var searchResultsSection: AnyView {
        let results = searchResults
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text(results.isEmpty ? "No results" : "Results")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .textCase(.uppercase)
                    .tracking(0.6)
                if results.isEmpty {
                    VStack(spacing: 8) {
                        WhisperMeetDoodle(symbol: "magnifyingglass", height: 120)
                        Text("Nothing matches “\(searchQuery)”")
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, entry in
                            Button {
                                Haptics.tap()
                                searchFocused = false
                                entry.action()
                            } label: {
                                HStack(spacing: 12) {
                                    iconTile(entry.icon)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.title)
                                            .font(.body)
                                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        Text(entry.group)
                                            .font(.caption)
                                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(.rect)
                            }
                            .buttonStyle(WhisperMenuPressStyle())
                            if idx < results.count - 1 { divider }
                        }
                    }
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                    }
                }
            }
        )
    }

    // MARK: - Branded rows

    /// Whisper One — the membership row wears the brand: wordmark tile on
    /// ink, warm-orange ONE pill, and a proper subtitle. No generic glyph.
    private var whisperOneRow: some View {
        Button {
            Haptics.tap()
            activeSheet = .whisperOne
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(WhisperTheme.ink(colorScheme))
                        .frame(width: 32, height: 32)
                    Image("WhisperLogo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 16)
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Whisper One")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("ONE")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                LinearGradient(
                                    colors: [
                                        WhisperAvatarPalette.backdrop,
                                        Color(red: 0.93, green: 0.42, blue: 0.20),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                    }
                    Text("Membership · badge, perks & early access")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
    }

    /// Branded log-out confirmation — replaces the instant sign-out with
    /// the same Whisper action sheet used across the app.
    private func presentLogoutConfirm() {
        let handle = auth.currentUser.username ?? LeaderboardService.shared.savedUsername
        actionMenu = WhisperActionMenuModel(
            title: handle.map { "Log out of @\($0)?" } ?? "Log out of Whisper?",
            subtitle: "Your account stays safe — you can log back in anytime.",
            actions: [
                WhisperMenuAction(icon: "rectangle.portrait.and.arrow.right", title: "Log out", isDestructive: true) {
                    auth.signOut()
                    close()
                }
            ],
            isConfirmStyle: true
        )
    }

    // MARK: - IG regroup extras (activity counts · where you're logged in · global sign-out)

    @State private var activityPostsCount: Int? = nil
    @State private var activitySavedCount: Int? = nil

    /// Quiet uppercase group kicker between section clusters — the web
    /// settings' IG grammar.
    private func groupKicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black))
            .tracking(1.3)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }

    private func activityCountRow(icon: String, title: String, count: Int?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 26)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(WhisperTheme.ink(colorScheme).opacity(0.07)))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 10)
    }

    private func activityInfoRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    /// "Where you're logged in" — a real DEVICE CARD (web parity): the
    /// device glyph tile, the model with a THIS DEVICE chip and an "Active
    /// now" live dot, the OS + app version line, then Account / Signed in as
    /// two clean key‑value rows. One session is what Supabase exposes to the
    /// client, so the card is honest about that.
    private var whereLoggedInRow: some View {
        let user = SupabaseService.shared.client.auth.currentUser
        let email = user?.email ?? "—"
        let signedIn: String = {
            guard let d = user?.lastSignInAt else { return "—" }
            let f = DateFormatter()
            f.dateFormat = "MMM d, yyyy · h:mm a"
            return f.string(from: d)
        }()
        let device = UIDevice.current
        let isPad = device.userInterfaceIdiom == .pad
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
        let live = Color(red: 0.13, green: 0.75, blue: 0.43)
        let ink = WhisperTheme.ink(colorScheme)
        let muted = WhisperTheme.muted(colorScheme)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                iconTile(isPad ? "ipad" : "iphone")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where you're logged in")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ink)
                    Text("1 active session on this phone")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isPad ? "ipad" : "iphone")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .background(WhisperTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(device.model)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                            Text("THIS DEVICE")
                                .font(.system(size: 9.5, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(WhisperTheme.surface(colorScheme), in: Capsule())
                                .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
                        }
                        Text("\(device.systemName) \(device.systemVersion) · Whisper \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        Circle().fill(live).frame(width: 7, height: 7)
                        Text("Active now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(live)
                    }
                }
                .padding(12)

                Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5)

                VStack(spacing: 0) {
                    sessionKeyValue("Account", email)
                    Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5).padding(.leading, 12)
                    sessionKeyValue("Signed in", signedIn)
                }
            }
            .background(WhisperTheme.card(colorScheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
            }

            Text("Whisper can only see this phone's session. To end every other login, use Sign out of all devices below.")
                .font(.caption2)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func sessionKeyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var memberSinceLine: String {
        guard let d = SupabaseService.shared.client.auth.currentUser?.createdAt else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }

    /// Live post + saved counts for "Your activity" — head-only count
    /// queries, fetched once per settings visit.
    private func loadActivityCounts() async {
        guard activityPostsCount == nil else { return }
        let uid = AccountStorage.currentUserID
        guard !uid.isEmpty else {
            activityPostsCount = 0
            activitySavedCount = 0
            return
        }
        let generation = AccountStorage.generation
        async let postsRead = try? await SupabaseService.shared.client
            .from("whisper_posts")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: uid)
            .execute()
        async let savedRead = try? await SupabaseService.shared.client
            .from("whisper_bookmarks")
            .select("post_id", head: true, count: .exact)
            .eq("user_id", value: uid)
            .execute()
        let (posts, saved) = await (postsRead, savedRead)
        guard !Task.isCancelled, generation == AccountStorage.generation,
              uid.caseInsensitiveCompare(AccountStorage.currentUserID) == .orderedSame else { return }
        activityPostsCount = posts?.count
        activitySavedCount = saved?.count
    }

    /// "Sign out of all devices" — ends every Supabase session everywhere
    /// (global scope), then runs the normal local sign-out.
    private func presentGlobalSignOutConfirm() {
        actionMenu = WhisperActionMenuModel(
            title: "Sign out of all devices?",
            subtitle: "Every session everywhere is ended — including this one. You can log back in anytime.",
            actions: [
                WhisperMenuAction(icon: "rectangle.portrait.and.arrow.right", title: "Sign out everywhere", isDestructive: true) {
                    guard !isSigningOutEverywhere else { return }
                    isSigningOutEverywhere = true
                    let generation = AccountStorage.generation
                    Task {
                        defer { isSigningOutEverywhere = false }
                        do {
                            try await SupabaseService.shared.client.auth.signOut(scope: .global)
                            guard generation == AccountStorage.generation else { return }
                            auth.signOut()
                            close()
                        } catch {
                            guard generation == AccountStorage.generation else { return }
                            signOutError = "Other sessions could not be revoked. Check your connection and try again."
                        }
                    }
                }
            ],
            isConfirmStyle: true
        )
    }

    /// Brand footer — wordmark instead of a bare caption line.
    private var brandFooter: some View {
        VStack(spacing: 6) {
            WhisperWordmark(size: 20)
            Text("A little closer, every day.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 32)
    }

    // MARK: - Sections

    /// Tappable hero card — avatar, name, handle, and an Edit pill. The
    /// whole card opens Edit Profile (iOS-Settings Apple-ID-row pattern).
    private var accountHeader: some View {
        Button {
            Haptics.tap()
            activeSheet = .editProfile
        } label: {
            HStack(spacing: 14) {
                WhisperAvatar(username: auth.currentUser.username ?? "you", size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.currentUser.displayName ?? auth.currentUser.formattedName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    if let username = auth.currentUser.username ?? LeaderboardService.shared.savedUsername {
                        Text("@\(username)")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text("Edit")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
            }
            .padding(16)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
            }
            .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
    }

    private func celebrationBanner(_ pending: ActiveSheet) -> some View {
        Button {
            Haptics.success()
            switch pending {
            case .celebrateCoach: coach.markCelebrated()
            case .celebrateVerified: verification.markCelebrated()
            default: break
            }
            activeSheet = pending
        } label: {
            HStack(spacing: 12) {
                iconTile("party.popper", tint: Color(red: 0.13, green: 0.55, blue: 0.96))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending == .celebrateCoach ? "You're approved as a coach!" : "You're verified!")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Tap to view your welcome")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color(red: 0.13, green: 0.55, blue: 0.96).opacity(colorScheme == .dark ? 0.12 : 0.06), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(red: 0.13, green: 0.55, blue: 0.96).opacity(0.3), lineWidth: 1)
        }
    }

    /// CRASH FIX — the `AnyView` type erasure here (and in `sheetView`/
    /// `studioView`) is deliberate and must stay. This screen's body has
    /// ~20 sections in one VStack; without erasure every section inlines its
    /// full generic payload into the body's mangled type. On TestFlight
    /// (release) builds the Swift runtime instantiates that metadata lazily
    /// from the mangled name the moment the sheet is presented, and the
    /// demangler recursion overflowed the main-thread stack — a hard
    /// EXC_BAD_ACCESS on the stack guard (crash in `swift_getTypeByMangledName`
    /// under `WhisperSettingsView.body`). Debug/simulator builds never hit it.
    /// Erasing each section caps the type depth. Do not "clean this up".
    private func section<Content: View>(title: String?, @ViewBuilder _ content: () -> Content) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .padding(.leading, 16)
                }
                VStack(spacing: 0) { content() }
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                    }
            }
        )
    }

    // MARK: - Modal content (type-erased)

    /// Sheet content for `activeSheet`, type-erased to `AnyView`.
    ///
    /// A 24-case `switch` in a ViewBuilder closure builds a `_ConditionalContent`
    /// tree nested one level per case, which fed the same runtime-demangler
    /// stack overflow described on `section(title:_:)`. Returning `AnyView`
    /// keeps the `.sheet` modifier's generic parameter flat. Do not inline
    /// this back into the modifier.
    private func sheetView(for sheet: ActiveSheet) -> AnyView {
        switch sheet {
        case .coachAccess: return AnyView(WhisperCoachAccessView().whisperSheetBorder())
        case .editProfile: return AnyView(WhisperEditProfileView().whisperSheetBorder())
        case .phone: return AnyView(WhisperPhoneSheet().whisperSheetBorder())
        case .findFriends: return AnyView(WhisperFindFriendsView().whisperSheetBorder())
        case .about: return AnyView(aboutSheet.whisperSheetBorder())
        case .coachApply: return AnyView(WhisperCoachApplicationView().whisperSheetBorder())
        case .verifyApply: return AnyView(WhisperVerificationApplicationView().whisperSheetBorder())
        case .accountApps: return AnyView(WhisperAccountApplicationsDashboardView().whisperSheetBorder())
        case .reportsDashboard: return AnyView(WhisperReportsDashboardView().whisperSheetBorder())
        case .myCoaches: return AnyView(WhisperMyCoachesView().whisperSheetBorder())
        case .whisperOne: return AnyView(WhisperOnePaywallView())
        case .jasperPromo: return AnyView(WhisperWhisperPromoPage().whisperSheetBorder())
        case .coachRate: return AnyView(WhisperCoachRateSheet().whisperSheetBorder())
        case .mySubscriptions: return AnyView(WhisperMyCoachSubscriptionsView().whisperSheetBorder())
        case .myArticles: return AnyView(WhisperMyArticlesView().whisperSheetBorder())
        case .safetyInfo: return AnyView(WhisperSafetyInfoView().whisperSheetBorder())
        case .decisions: return AnyView(WhisperDecisionsView().id(AccountStorage.generation).whisperSheetBorder())
        case .badgeActivateCoach: return AnyView(WhisperBadgeActivateView(role: .coach))
        case .badgeActivateVerified: return AnyView(WhisperBadgeActivateView(role: .verified))
        case .creatorLink: return AnyView(WhisperCreatorLinkSheet().whisperSheetBorder())
        case .reportProblem: return AnyView(WhisperReportProblemSheet().whisperSheetBorder())
        case .analytics: return AnyView(WhisperAnalyticsView().whisperSheetBorder())
        case .savedPosts: return AnyView(WhisperSavedPostsPage())
        case .celebrateCoach:
            return AnyView(
                WhisperCoachWelcomeView(onTakeTour: {
                    activeSheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activeStudio = .coachStudio
                    }
                })
                .whisperSheetBorder()
            )
        case .celebrateVerified:
            return AnyView(WhisperVerifiedWelcomeView().whisperSheetBorder())
        }
    }

    /// Full-screen studio content for `activeStudio`, type-erased for the
    /// same runtime-demangler crash reason as `sheetView(for:)`.
    private func studioView(for studio: ActiveStudio) -> AnyView {
        switch studio {
        case .coachStudio: return AnyView(WhisperCoachProgramsView())
        case .coachClients: return AnyView(WhisperCoachClientsView())
        case .creatorPayouts: return AnyView(WhisperCreatorPayoutsView())
        case .coachEarnings: return AnyView(WhisperCoachEarningsView())
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 58)
    }

    /// Rounded-square icon tile — gives every settings row the modern
    /// iOS-Settings look instead of a bare glyph floating in space.
    /// Quiet by default: a whisper-subtle fill with a medium-weight glyph.
    private func iconTile(_ icon: String, tint: Color? = nil) -> some View {
        let color = tint ?? WhisperTheme.ink(colorScheme)
        return Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(colorScheme == .dark ? 0.13 : 0.06), in: .rect(cornerRadius: 10))
    }

    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconTile(icon)
                Text(title)
                    .font(.body)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
    }

    /// Special version of `navRow` for the follow-requests entry; mirrors
    /// the other rows but adds a red count pill on the right when there
    /// are pending requests waiting on the user.
    private var followRequestsNavRow: some View {
        let count = followRequests.pendingIncomingCount
        return HStack(spacing: 12) {
            iconTile("person.crop.circle.badge.questionmark")
            Text("Follow requests")
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    private func navRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            iconTile(icon)
            Text(title)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    private func row(icon: String, title: String, toggle: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconTile(icon)
            Text(title)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            Toggle(title, isOn: toggle)
                .labelsHidden()
                .tint(WhisperTheme.ink(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func destructiveRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(colorScheme == .dark ? 0.13 : 0.06), in: .rect(cornerRadius: 10))
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
    }

    // MARK: - Appearance

    @State private var appearance = WhisperAppearance.shared

    /// Dark mode now always uses true black; retained as an informational row.
    private var pitchBlackRow: some View {
        HStack(spacing: 12) {
            iconTile("circle.lefthalf.filled")
            VStack(alignment: .leading, spacing: 2) {
                Text("Pitch black")
                    .font(.body)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("True black dark mode · easier on OLED")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Image(systemName: "checkmark").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var aboutSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 16) {
                    WhisperWordmark(size: 48)
                        .padding(.top, 32)
                    Text("Whisper")
                        .font(.title.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("The social side of Whisper.\nQuiet wins. Loud progress.")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 24)
                    Spacer()
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { activeSheet = nil }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }
}
