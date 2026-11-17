import SwiftUI

/// The Workspace — the full-screen hub opened from the briefcase in the
/// inbox header. Uses the shared brand accents and quiet work surfaces while
/// staying iOS-native: meetings first (new meeting / join by code — the
/// same rooms as web), then your desk, then one studio card per role the
/// signed-in user actually holds. Roles are re-checked on appear so a
/// freshly approved coach shows up immediately.
struct WhisperRoleToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var coach = WhisperCoachService.shared
    @State private var brands = WhisperBrandService.shared
    @State private var coachRequests = WhisperCoachRequestService.shared
    @State private var recruiter = WhisperRecruiterService.shared
    @State private var businessWorkspace: WhisperBusinessWorkspaceService = .shared

    /// Every destination the hub can open. All are full screens with their
    /// own navigation chrome; the monthly-rate editor is the one small
    /// form that stays a sheet.
    private enum Tool: Int, Identifiable {
        case coachStudio, coachPrograms, coachEarnings, coachMessaging
        case creatorStudio, mySponsorships, creatorMessaging
        case brandDashboard, brandEditor, brandMessaging
        case sharedCalendar
        case recruiterDashboard
        case meetings, notebook, businessPlus, workDesk
        var id: Int { rawValue }
    }
    @State private var activeTool: Tool?
    @State private var presentRateSheet: Bool = false
    @State private var searchWorkspace: Bool = false

    private var myUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
    }

    private var firstName: String {
        let name = myUsername.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "there" : name
    }

    private var myBadge: UserBadge {
        UserVerificationService.shared.badge(forUsername: myUsername)
    }

    private var isCreator: Bool {
        myBadge == .verified || myBadge == .moderator || myBadge == .admin || myBadge == .owner
    }

    // Web Workspace accents — exact portal colors so both apps read as one.
    /// Shared brand stops; legacy property names retained for existing doors.
    private var workspaceMint: Color { WhisperBrandGradient.rose }
    private var mintDeep: Color { WhisperBrandGradient.amber }
    /// #E8853D — coach ember.
    private var coachAccent: Color { Color(red: 0.910, green: 0.522, blue: 0.239) }
    /// #7059E8 — recruiter violet.
    private var recruiterAccent: Color { Color(red: 0.439, green: 0.349, blue: 0.910) }
    /// Creator studio door shares the brand accent.
    private var creatorAccent: Color { workspaceMint }
    private var calendarBlue: Color { Color(red: 0.23, green: 0.51, blue: 0.96) }

    private var hasAnyRole: Bool {
        coach.isMeCoach || isCreator || brands.myBrand != nil || recruiter.isMeRecruiter || businessWorkspace.context != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        greetingHeader
                        Button { searchWorkspace = true } label: {
                            Label("Search workspace", systemImage: "magnifyingglass").font(.subheadline).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 16).background(.quaternary, in: Capsule())
                        }.buttonStyle(.plain)
                        .sheet(isPresented: $searchWorkspace) { WorkspaceSearchView().id(AccountStorage.currentUserID) }
                        deskGrid
                        studiosHeader
                        if coach.isMeCoach {
                            coachSection
                        }
                        if isCreator {
                            creatorSection
                        }
                        if brands.myBrand != nil {
                            brandSection
                        }
                        if recruiter.isMeRecruiter {
                            recruiterSection
                        }
                        if let business = businessWorkspace.context {
                            studioCard(accent: WhisperBrandGradient.accent, icon: "building.2", title: "Business+", hint: business.displayName) {
                                studioRow(icon: "person.2", tint: WhisperBrandGradient.accent, title: "Company workspace", subtitle: "People, roles & business agenda") { activeTool = .businessPlus }
                            }
                        }
                        if !hasAnyRole {
                            studiosHint
                        }
                        footerNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .whisperEdgeBack { dismiss() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .task {
                await coach.refreshMyStatus()
                await brands.refreshMyBrand()
                await coachRequests.refresh()
                await recruiter.refreshMyStatus()
                await businessWorkspace.refreshAccess()
                if !myUsername.isEmpty {
                    await UserVerificationService.shared.preload(usernames: [myUsername])
                }
            }
            .fullScreenCover(item: $activeTool, onDismiss: { Task { await businessWorkspace.refreshAccess() } }) { tool in
                switch tool {
                case .coachStudio: WhisperCoachClientsView()
                case .coachPrograms: WhisperCoachProgramsView()
                case .coachEarnings: WhisperCoachEarningsView()
                case .coachMessaging: WhisperRoleMessagingToolsView(role: .coach)
                case .creatorStudio: WhisperCreatorDashboardView()
                case .mySponsorships: WhisperMySponsorshipsView()
                case .creatorMessaging: WhisperRoleMessagingToolsView(role: .creator)
                case .brandDashboard: WhisperBrandDashboardView()
                case .brandEditor: WhisperBrandEditorView()
                case .brandMessaging: WhisperRoleMessagingToolsView(role: .brand)
                case .sharedCalendar: WhisperCalendarView()
                case .recruiterDashboard: WhisperRecruiterDashboardView()
                case .meetings: WhisperMeetingsView()
                case .notebook: WhisperMeetingNotesListView().id(AccountStorage.currentUserID)
                case .businessPlus: WhisperBusinessWorkspaceView()
                case .workDesk: WorkspaceWorkView().id(AccountStorage.currentUserID)
                }
            }
            .sheet(isPresented: $presentRateSheet) {
                WhisperCoachRateSheet()
                    .whisperSheetBorder()
            }
        }
    }

    // MARK: - Greeting (web parity: kicker + "Welcome back")

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WORKSPACE")
                .font(.system(size: 11, weight: .black))
                .tracking(2.4)
                .foregroundStyle(workspaceMint)
            Text("Welcome back, \(firstName).")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Every tool Whisper gives you — one desk. Meetings and Jasper come with every role.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Your desk (universal tools — web parity tiles)

    private var deskGrid: some View {
        VStack(spacing: 10) {
            deskTile(icon: "person.2", label: "Teams", hint: "Set up a team, add people or update roles") { activeTool = .businessPlus }
            deskTile(icon: "square.stack.3d.up", label: "Work desk", hint: "Decisions, client deliveries & approvals") { activeTool = .workDesk }
            deskTile(
                icon: "video.fill",
                label: "Meet",
                hint: "Start, join, schedule & meeting history"
            ) { activeTool = .meetings }
            deskTile(
                icon: "note.text",
                label: "Meeting library",
                hint: "Meeting notes, transcripts & recordings"
            ) { activeTool = .notebook }
            deskTile(
                icon: "calendar",
                label: "Calendar",
                hint: "Events, RSVPs & planning — tag your team"
            ) { activeTool = .sharedCalendar }
        }
    }

    private func deskTile(
        icon: String,
        label: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(workspaceMint)
                    .frame(width: 40, height: 40)
                    .background(workspaceMint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
    }

    // MARK: - Studios

    private var studiosHeader: some View {
        Text("YOUR STUDIOS")
            .font(.system(size: 11, weight: .black))
            .tracking(2)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.top, 6)
    }

    private var coachSection: some View {
        let pending = coachRequests.incoming.filter { $0.status == "pending" }.count
        return studioCard(
            accent: coachAccent,
            icon: "dumbbell.fill",
            title: "Coach Studio",
            hint: "Clients, plans & earnings"
        ) {
            studioRow(icon: "person.2.fill", tint: coachAccent, title: "Clients & check-ins", subtitle: "Plans, check-ins, client cards", badge: pending > 0 ? "\(pending)" : nil) { activeTool = .coachStudio }
            studioDivider
            studioRow(icon: "list.clipboard.fill", tint: coachAccent, title: "Programs", subtitle: "Build and send training programs") { activeTool = .coachPrograms }
            studioDivider
            studioRow(icon: "banknote.fill", tint: coachAccent, title: "Earnings & payouts", subtitle: "Balance, bank account, payouts") { activeTool = .coachEarnings }
            studioDivider
            studioRow(icon: "tag.fill", tint: coachAccent, title: "Monthly rate", subtitle: "What clients pay per month") { presentRateSheet = true }
            studioDivider
            studioRow(icon: "text.bubble.fill", tint: coachAccent, title: "Messaging tools", subtitle: "Check-in templates & quick replies") { activeTool = .coachMessaging }
        }
    }

    private var creatorSection: some View {
        studioCard(
            accent: creatorAccent,
            icon: "chart.bar.fill",
            title: "Creator Studio",
            hint: "Analytics, WPP & sponsorships"
        ) {
            studioRow(icon: "chart.line.uptrend.xyaxis", tint: creatorAccent, title: "Analytics & WPP", subtitle: "Score, reach & your ad-revenue share") { activeTool = .creatorStudio }
            studioDivider
            studioRow(icon: "handshake.fill", tint: creatorAccent, title: "My sponsorships", subtitle: "Applications, deals, deliverables") { activeTool = .mySponsorships }
            studioDivider
            studioRow(icon: "banknote.fill", tint: creatorAccent, title: "Earnings & payouts", subtitle: "Balance, bank account, payouts") { activeTool = .coachEarnings }
            studioDivider
            studioRow(icon: "text.bubble.fill", tint: creatorAccent, title: "Messaging tools", subtitle: "Collab & sponsorship quick replies") { activeTool = .creatorMessaging }
        }
    }

    private var brandSection: some View {
        let brandAccent = Color(red: 0.353, green: 0.373, blue: 0.910) // #5A5FE8 — business indigo
        return studioCard(
            accent: brandAccent,
            icon: "briefcase.fill",
            title: "Brand HQ",
            hint: "Deals, terms & escrow"
        ) {
            studioRow(icon: "rectangle.grid.2x2.fill", tint: brandAccent, title: "Brand dashboard", subtitle: "Applications, terms, escrow") { activeTool = .brandDashboard }
            studioDivider
            studioRow(icon: "square.and.pencil", tint: brandAccent, title: "Edit brand profile", subtitle: "Logo, requirements, payment terms") { activeTool = .brandEditor }
            studioDivider
            studioRow(icon: "text.bubble.fill", tint: brandAccent, title: "Messaging tools", subtitle: "Creator outreach & deal templates") { activeTool = .brandMessaging }
        }
    }

    private var recruiterSection: some View {
        studioCard(
            accent: recruiterAccent,
            icon: "person.crop.badge.magnifyingglass.fill",
            title: "Recruiter HQ",
            hint: "Today, pipeline, inbox & insights"
        ) {
            studioRow(icon: "binoculars.fill", tint: recruiterAccent, title: "Open Recruiter HQ", subtitle: "The full recruiting desk — six views") { activeTool = .recruiterDashboard }
        }
    }

    /// Quiet hint when no studios are unlocked — meetings and the desk are
    /// always there, so the Workspace is never empty.
    private var studiosHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.body)
                .foregroundStyle(workspaceMint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Studios unlock with a role")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Become a coach, creator, brand, or recruiter and its studio appears here.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var footerNote: some View {
        Text("This desk lives in your pocket — the same rooms, notes, and studios as workspace.mydailywhisper.com.")
            .font(.caption2)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.top, 2)
    }

    // MARK: - Building blocks

    /// One studio door card — gradient chip header + tool rows, matching
    /// the web hub's door design.
    @ViewBuilder
    private func studioCard<Content: View>(
        accent: Color,
        icon: String,
        title: String,
        hint: String,
        @ViewBuilder _ rows: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            Rectangle()
                .fill(WhisperTheme.hairline(colorScheme))
                .frame(height: 0.5)

            VStack(spacing: 0) { rows() }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var studioDivider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    private func studioRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color(red: 0.98, green: 0.20, blue: 0.28), in: Capsule())
                }
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
