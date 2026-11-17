import SwiftUI
import AuthenticationServices

// MARK: - Shared bits

/// Status pill used across sponsorship applications and payments.
struct WhisperSponsorStatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: String

    private var style: (Color, String) {
        switch status {
        case "pending":   return (Color(red: 0.92, green: 0.63, blue: 0.18), "Pending")
        case "countered": return (Color(red: 0.42, green: 0.36, blue: 0.90), "New terms")
        case "accepted", "active", "released":
            return (Color(red: 0.13, green: 0.65, blue: 0.36), status == "released" ? "Released" : (status == "active" ? "Active" : "Accepted"))
        case "denied":    return (Color.red, "Denied")
        case "refunded":  return (Color.red, "Refunded")
        case "withdrawn": return (Color.gray, "Withdrawn")
        default:          return (Color.gray, status.capitalized)
        }
    }

    var body: some View {
        Text(style.1)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.0.opacity(0.15), in: Capsule())
            .foregroundStyle(style.0)
    }
}

private func sponsorAmountText(_ cents: Int, _ basis: String) -> String {
    let b = WhisperSponsorBasis(rawValue: basis) ?? .perPost
    return "\(WhisperBillingService.formatCents(cents)) \(b.shortLabel)"
}

// MARK: - Creator sponsorship hub

/// The creator side: sent applications (accept counters / withdraw), active
/// deals with post tracking, and the escrow payment ledger.
struct WhisperMySponsorshipsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var applications: [WhisperSponsorApplication] = []
    @State private var deals: [WhisperSponsorDeal] = []
    @State private var payments: [WhisperSponsorPayment] = []
    @State private var trackedPosts: [WhisperSponsorPost] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var trackingDeal: WhisperSponsorDeal?
    @State private var showBrandDirectory: Bool = false
    @State private var connectStatus: WhisperConnectStatus?
    @State private var earnings: WhisperCreatorEarnings?
    @State private var showEarnings: Bool = false

    private var me: String { AccountStorage.currentUserID.lowercased() }
    private var myDeals: [WhisperSponsorDeal] {
        deals.filter { $0.creatorUserId.lowercased() == me }
    }
    private var accent: Color { WhisperTheme.ink(colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if isLoading && applications.isEmpty && myDeals.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        } else {
                            if let earnings,
                               !myDeals.isEmpty || earnings.pendingCents > 0 || earnings.releasedCents > 0 {
                                earningsCard(earnings)
                            }
                            if connectStatus?.payoutsEnabled != true && !myDeals.isEmpty {
                                bankReminderCard
                            }
                            if applications.isEmpty && myDeals.isEmpty {
                                emptyState
                            }
                            if !myDeals.isEmpty {
                                dealsSection
                            }
                            if !applications.isEmpty {
                                applicationsSection
                            }
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .whisperRefreshable { await load() }
            }
            .navigationTitle("Sponsorships")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showBrandDirectory = true
                    } label: {
                        Image(systemName: "building.2")
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
            }
            .sheet(item: $trackingDeal) { deal in
                WhisperTrackPostSheet(deal: deal) {
                    Task { await load() }
                }
            }
            .fullScreenCover(isPresented: $showBrandDirectory) {
                WhisperBrandDirectoryView()
            }
            .sheet(isPresented: $showEarnings) {
                WhisperCoachEarningsView()
            }
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: "hands.clap", height: 144)
            Text("No sponsorships yet")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Browse sponsor brands, see exactly what they pay, and apply. Your applications and deals live here.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 24)
            Button {
                Haptics.tap()
                showBrandDirectory = true
            } label: {
                Text("Browse brands")
                    .font(.footnote.weight(.bold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(accent, in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// The creator/athlete payment gateway — escrow totals + payout status,
    /// mirroring the coach earnings experience.
    private func earningsCard(_ earnings: WhisperCreatorEarnings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.13, green: 0.65, blue: 0.36).opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: "wallet.bifold.fill")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                }
                Text("Your earnings")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Button {
                    Haptics.tap()
                    showEarnings = true
                } label: {
                    HStack(spacing: 3) {
                        Text("Payouts & bank")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                earningsStat(
                    "In escrow for you",
                    earnings.pendingCents,
                    Color(red: 0.92, green: 0.63, blue: 0.18)
                )
                earningsStat(
                    "Paid out to date",
                    earnings.releasedCents,
                    Color(red: 0.13, green: 0.65, blue: 0.36)
                )
            }
            Text(earnings.payoutsEnabled
                 ? "Your bank is linked — released funds transfer automatically."
                 : "Link your bank in Settings → Payments so released funds can reach you.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func earningsStat(_ title: String, _ cents: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(WhisperBillingService.formatCents(cents))
                .font(.title3.weight(.black).monospacedDigit())
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var bankReminderCard: some View {
        Button {
            Haptics.tap()
            showEarnings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "building.columns")
                    .font(.body)
                    .foregroundStyle(Color(red: 0.92, green: 0.63, blue: 0.18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Link your bank to get paid")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Sponsorship payments stay pending until a payout account is connected — takes about a minute.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(12)
            .background(Color(red: 0.92, green: 0.63, blue: 0.18).opacity(0.06), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(red: 0.92, green: 0.63, blue: 0.18).opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active deals")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            ForEach(myDeals) { deal in
                dealCard(deal)
            }
        }
    }

    private func dealCard(_ deal: WhisperSponsorDeal) -> some View {
        let dealPayments = payments.filter { $0.dealId == deal.id }
        let dealPosts = trackedPosts.filter { $0.dealId == deal.id }
        let pendingNet = dealPayments.filter { $0.status == "pending" }.reduce(0) { $0 + $1.netCents }
        let releasedNet = dealPayments.filter { $0.status == "released" }.reduce(0) { $0 + $1.netCents }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deal.brandCompany ?? "Brand")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(sponsorAmountText(deal.amountCents, deal.basis))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
                Spacer()
                WhisperSponsorStatusPill(status: deal.status)
            }
            HStack(spacing: 8) {
                ledgerStat("Pending", WhisperBillingService.formatCents(pendingNet), Color(red: 0.92, green: 0.63, blue: 0.18))
                ledgerStat("Released", WhisperBillingService.formatCents(releasedNet), Color(red: 0.13, green: 0.65, blue: 0.36))
                ledgerStat("Posts tracked", "\(dealPosts.count)", nil)
            }
            if let notes = deal.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(3)
            }
            if deal.status == "active" {
                Button {
                    Haptics.tap()
                    trackingDeal = deal
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                        Text("Link a sponsored post")
                    }
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    /// Web parity: the deal-card stat tiles — centered value over label in a
    /// rounded box (MySponsorships DealCard grid).
    private func ledgerStat(_ title: String, _ value: String, _ color: Color?) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.black).monospacedDigit())
                .foregroundStyle(color ?? WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(WhisperTheme.surface(colorScheme).opacity(0.6), in: .rect(cornerRadius: 12))
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My applications")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            ForEach(applications) { app in
                applicationCard(app)
            }
        }
    }

    private func applicationCard(_ app: WhisperSponsorApplication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.brandCompany ?? "Brand")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Asked \(sponsorAmountText(app.desiredAmountCents, app.desiredBasis))")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                WhisperSponsorStatusPill(status: app.status)
            }
            if app.status == "countered", let cents = app.termsAmountCents {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Brand counter-offer: \(sponsorAmountText(cents, app.termsBasis ?? app.desiredBasis))\(app.termsExclusive ? " · exclusive" : "")")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(accent)
                    if let deliverables = app.termsDeliverables, !deliverables.isEmpty {
                        Text("Deliverables: \(deliverables)")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    if let notes = app.termsNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    if let expires = app.termsExpiresAt,
                       let date = WhisperBackendService.parseISO(expires) {
                        Label("Offer expires \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 0.92, green: 0.63, blue: 0.18))
                    }
                    HStack(spacing: 8) {
                        Button {
                            Haptics.tap()
                            Task { await respond(app, action: "accept") }
                        } label: {
                            Text("Accept terms")
                                .font(.footnote.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(WhisperTheme.ink(colorScheme), in: Capsule())
                                .foregroundStyle(WhisperTheme.surface(colorScheme))
                        }
                        .buttonStyle(.plain)
                        Button {
                            Haptics.warning()
                            Task { await respond(app, action: "withdraw") }
                        } label: {
                            Text("Decline")
                                .font(.footnote.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(WhisperTheme.surface(colorScheme), in: Capsule())
                                .foregroundStyle(.red)
                                .overlay {
                                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(accent.opacity(0.06), in: .rect(cornerRadius: 12))
            } else if app.status == "pending" {
                Button {
                    Haptics.warning()
                    Task { await respond(app, action: "withdraw") }
                } label: {
                    Text("Withdraw")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func respond(_ app: WhisperSponsorApplication, action: String) async {
        do {
            try await WhisperBrandService.shared.creatorRespond(applicationId: app.id, action: action)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let apps = WhisperBrandService.shared.fetchApplications()
            async let dealData = WhisperBrandService.shared.fetchDeals()
            let (a, d) = try await (apps, dealData)
            applications = a.asCreator
            deals = d.deals
            payments = d.payments
            trackedPosts = d.posts
        } catch {
            errorMessage = error.localizedDescription
        }
        connectStatus = try? await WhisperBillingService.shared.fetchConnectStatus()
        earnings = try? await WhisperBrandService.shared.fetchCreatorEarnings()
    }
}

// MARK: - Track post sheet

/// Creator picks one of their recent posts to count toward a deal.
struct WhisperTrackPostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let deal: WhisperSponsorDeal
    var onTracked: () -> Void = {}

    @State private var posts: [WhisperPostRow] = []
    @State private var isLoading: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    private var accent: Color { WhisperTheme.ink(colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pick the post that fulfills your \(deal.brandCompany ?? "brand") sponsorship. Per-post payments release as soon as it's linked.")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        if isLoading {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if posts.isEmpty {
                            Text("No posts yet — publish your sponsored post first, then link it here.")
                                .font(.footnote)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .padding(.top, 20)
                        } else {
                            ForEach(posts) { post in
                                Button {
                                    Haptics.tap()
                                    Task { await track(post) }
                                } label: {
                                    postRow(post)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSubmitting)
                            }
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Link a post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task {
            isLoading = true
            defer { isLoading = false }
            posts = (try? await WhisperBrandService.shared.fetchMyRecentPosts()) ?? []
        }
    }

    private func postRow(_ post: WhisperPostRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: post.kind == "photo" ? "photo" : "text.alignleft")
                .font(.body)
                .foregroundStyle(accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(WhisperPostMeta.strip(from: post.caption).isEmpty ? "Untitled post" : WhisperPostMeta.strip(from: post.caption))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(2)
                if let created = post.created_at,
                   let date = WhisperBackendService.parseISO(created) {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            Spacer()
            Image(systemName: "link")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .contentShape(.rect)
    }

    private func track(_ post: WhisperPostRow) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await WhisperBrandService.shared.trackPost(dealId: deal.id, postId: post.id)
            Haptics.success()
            onTracked()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Brand dashboard

/// The brand side: incoming applications (accept / counter with editable
/// terms / deny), and active deals with escrow funding + tracked posts.
struct WhisperBrandDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var applications: [WhisperSponsorApplication] = []
    @State private var deals: [WhisperSponsorDeal] = []
    @State private var payments: [WhisperSponsorPayment] = []
    @State private var trackedPosts: [WhisperSponsorPost] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var respondingTo: WhisperSponsorApplication?
    @State private var showEditor: Bool = false
    @State private var fundingDealID: String?
    @State private var disputingPayment: WhisperSponsorPayment?
    @State private var disputeReason: String = "Deliverables were not met"
    /// Application currently confirming a quick deny from the card.
    @State private var confirmDenyApp: WhisperSponsorApplication?
    /// Application ID mid quick-approve/deny — dims + disables its card.
    @State private var actingAppID: String?

    private var me: String { AccountStorage.currentUserID.lowercased() }
    private var myDeals: [WhisperSponsorDeal] {
        deals.filter { $0.brandUserId.lowercased() == me }
    }
    private var openApplications: [WhisperSponsorApplication] {
        applications.filter { ["pending", "countered"].contains($0.status) }
    }
    private var decidedApplications: [WhisperSponsorApplication] {
        applications.filter { !["pending", "countered"].contains($0.status) }
    }
    private var accent: Color { WhisperTheme.ink(colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if isLoading && applications.isEmpty && myDeals.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        } else {
                            overviewStrip
                            if !openApplications.isEmpty {
                                sectionHeader("Applications", count: openApplications.count)
                                ForEach(openApplications) { app in
                                    brandApplicationCard(app)
                                }
                            }
                            if !myDeals.isEmpty {
                                sectionHeader("Deals", count: myDeals.count)
                                ForEach(myDeals) { deal in
                                    brandDealCard(deal)
                                }
                            }
                            if openApplications.isEmpty && myDeals.isEmpty {
                                emptyState
                            }
                            if !decidedApplications.isEmpty {
                                sectionHeader("History", count: decidedApplications.count)
                                ForEach(decidedApplications) { app in
                                    historyRow(app)
                                }
                            }
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .whisperRefreshable { await load() }
            }
            .navigationTitle("Brand Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showEditor = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
            }
            .sheet(item: $respondingTo) { app in
                WhisperSponsorRespondSheet(application: app) {
                    Task { await load() }
                }
            }
            .sheet(isPresented: $showEditor) {
                WhisperBrandEditorView()
            }
            .alert(
                "Deny this application?",
                isPresented: Binding(
                    get: { confirmDenyApp != nil },
                    set: { if !$0 { confirmDenyApp = nil } }
                )
            ) {
                Button("Deny", role: .destructive) {
                    if let app = confirmDenyApp {
                        Task { await quickRespond(app, action: "deny") }
                    }
                }
                Button("Cancel", role: .cancel) { confirmDenyApp = nil }
            } message: {
                Text("@\(confirmDenyApp?.creatorUsername ?? "The creator") won't be able to receive DMs from your brand afterward.")
            }
            .alert(
                "Dispute this payment?",
                isPresented: Binding(
                    get: { disputingPayment != nil },
                    set: { if !$0 { disputingPayment = nil } }
                )
            ) {
                TextField("Reason", text: $disputeReason)
                Button("Dispute & refund", role: .destructive) {
                    if let payment = disputingPayment {
                        Task { await dispute(payment) }
                    }
                }
                Button("Cancel", role: .cancel) { disputingPayment = nil }
            } message: {
                Text("The escrowed funds will be refunded to your card. Use this when the creator didn't meet their obligations.")
            }
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: "tray", height: 144)
            Text("No applications yet")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Creators who meet your requirements can apply from your brand profile. Applications land here for review.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(WhisperTheme.card(colorScheme), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
    }

    /// At-a-glance numbers across the whole brand account — open
    /// applications, active deals, and total escrow currently held.
    private var overviewStrip: some View {
        let escrowCents = payments
            .filter { payment in
                payment.status == "pending" && myDeals.contains { $0.id == payment.dealId }
            }
            .reduce(0) { $0 + $1.grossCents }
        let activeDeals = myDeals.filter { $0.status == "active" }.count
        return HStack(spacing: 10) {
            overviewStat("\(openApplications.count)", "Applications")
            overviewStat("\(activeDeals)", "Active deals")
            overviewStat(WhisperBillingService.formatCents(escrowCents), "In escrow")
        }
    }

    private func overviewStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
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

    private func brandApplicationCard(_ app: WhisperSponsorApplication) -> some View {
        let busy = actingAppID == app.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                WhisperAvatar(username: app.creatorUsername ?? "creator", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(app.creatorUsername ?? "creator")")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let followers = app.creatorFollowers {
                            Text("\(followers.formatted()) followers")
                        }
                        if app.creatorFollowers != nil && app.creatorAge != nil {
                            Text("·")
                        }
                        if let age = app.creatorAge {
                            Text("\(age) yrs")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer(minLength: 0)
                WhisperSponsorStatusPill(status: app.status)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sponsorAmountText(app.desiredAmountCents, app.desiredBasis))
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if app.status == "countered", let cents = app.termsAmountCents {
                    Text("You countered \(sponsorAmountText(cents, app.termsBasis ?? app.desiredBasis))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                } else {
                    Text("Requested rate")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }

            if let message = app.message, !message.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WhisperTheme.hairline(colorScheme))
                        .frame(width: 3)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(4)
                        .lineSpacing(2)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.success()
                    Task { await quickRespond(app, action: "accept") }
                } label: {
                    HStack(spacing: 5) {
                        if busy { ProgressView().controlSize(.mini).tint(WhisperTheme.surface(colorScheme)) }
                        Text("Approve")
                    }
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    respondingTo = app
                } label: {
                    Text("Modify")
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .overlay {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.warning()
                    confirmDenyApp = app
                } label: {
                    Text("Deny")
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                        .foregroundStyle(.red)
                        .overlay {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    /// One-tap approve/deny straight from the application card. Approving
    /// accepts the creator's asked terms exactly; the Modify path opens the
    /// full respond sheet for counter-offers.
    private func quickRespond(_ app: WhisperSponsorApplication, action: String) async {
        actingAppID = app.id
        errorMessage = nil
        defer { actingAppID = nil }
        do {
            try await WhisperBrandService.shared.respond(
                applicationId: app.id,
                action: action,
                termsBasis: action == "deny" ? nil : (WhisperSponsorBasis(rawValue: app.termsBasis ?? app.desiredBasis) ?? .perPost),
                termsAmountCents: action == "deny" ? nil : (app.termsAmountCents ?? app.desiredAmountCents),
                termsNotes: action == "deny" ? nil : app.termsNotes,
                termsDeliverables: action == "deny" ? nil : app.termsDeliverables,
                termsExclusive: action == "deny" ? nil : app.termsExclusive,
                expiresInDays: nil
            )
            Haptics.success()
            confirmDenyApp = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func brandDealCard(_ deal: WhisperSponsorDeal) -> some View {
        let dealPayments = payments.filter { $0.dealId == deal.id }
        let dealPosts = trackedPosts.filter { $0.dealId == deal.id }
        let pending = dealPayments.filter { $0.status == "pending" }
        let released = dealPayments.filter { $0.status == "released" }
        let totalLikes = dealPosts.reduce(0) { $0 + $1.likesCount }
        let totalComments = dealPosts.reduce(0) { $0 + $1.commentsCount }

        let pendingCents = pending.reduce(0) { $0 + $1.grossCents }
        let releasedCents = released.reduce(0) { $0 + $1.grossCents }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                WhisperAvatar(username: deal.creatorUsername ?? "creator", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(deal.creatorUsername ?? "creator")")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text(sponsorAmountText(deal.amountCents, deal.basis))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer(minLength: 0)
                WhisperSponsorStatusPill(status: deal.status)
            }
            HStack(spacing: 10) {
                dealStat(WhisperBillingService.formatCents(pendingCents), "In escrow", Color(red: 0.92, green: 0.63, blue: 0.18))
                dealStat(WhisperBillingService.formatCents(releasedCents), "Released", Color(red: 0.13, green: 0.65, blue: 0.36))
                dealStat("\(dealPosts.count)", "Posts live", WhisperTheme.ink(colorScheme))
            }
            if deal.exclusive || (deal.deliverables?.isEmpty == false) {
                VStack(alignment: .leading, spacing: 3) {
                    if deal.exclusive {
                        Text("Exclusive partnership")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accent)
                    }
                    if let deliverables = deal.deliverables, !deliverables.isEmpty {
                        Text("Deliverables: \(deliverables)")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(3)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.05), in: .rect(cornerRadius: 10))
            }
            if !dealPosts.isEmpty {
                HStack(spacing: 12) {
                    Text("Verified reach")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Label("\(totalLikes.formatted())", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Label("\(totalComments.formatted())", systemImage: "bubble.left.fill")
                        .font(.caption2)
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
            }
            ForEach(pending) { payment in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.92, green: 0.63, blue: 0.18))
                        .frame(width: 6, height: 6)
                    Text("\(WhisperBillingService.formatCents(payment.grossCents)) in escrow\(payment.requiresPost ? " · awaiting post" : "")")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Spacer()
                    Button {
                        Haptics.warning()
                        disputeReason = "Deliverables were not met"
                        disputingPayment = payment
                    } label: {
                        Label("Dispute", systemImage: "exclamationmark.shield")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
            }
            Text(deal.basisEnum == .perPost
                 ? "Funds are held by Whisper and release to the creator as each sponsored post goes live."
                 : "Funds are held by Whisper and release at the end of the week once the creator's posts are verified.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            if deal.status == "active" {
                Button {
                    Haptics.tap()
                    Task { await fund(deal) }
                } label: {
                    HStack(spacing: 6) {
                        if fundingDealID == deal.id { ProgressView().tint(WhisperTheme.surface(colorScheme)) }
                        Image(systemName: "lock.shield")
                        Text("Fund \(WhisperBillingService.formatCents(deal.amountCents)) into escrow")
                    }
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                }
                .buttonStyle(.plain)
                .disabled(fundingDealID != nil)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func dealStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
    }

    private func historyRow(_ app: WhisperSponsorApplication) -> some View {
        HStack(spacing: 10) {
            WhisperAvatar(username: app.creatorUsername ?? "creator", size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("@\(app.creatorUsername ?? "creator")")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text(sponsorAmountText(app.desiredAmountCents, app.desiredBasis))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            WhisperSponsorStatusPill(status: app.status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func dispute(_ payment: WhisperSponsorPayment) async {
        errorMessage = nil
        do {
            try await WhisperBrandService.shared.disputePayment(
                paymentId: payment.id,
                reason: disputeReason
            )
            Haptics.success()
            disputingPayment = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fund(_ deal: WhisperSponsorDeal) async {
        fundingDealID = deal.id
        errorMessage = nil
        defer { fundingDealID = nil }
        do {
            let url = try await WhisperBrandService.shared.fundDeal(dealId: deal.id)
            await MainActor.run {
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "whisper") { _, _ in
                    Task { await load() }
                }
                session.presentationContextProvider = WebAuthPresenter.shared
                session.start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let apps = WhisperBrandService.shared.fetchApplications()
            async let dealData = WhisperBrandService.shared.fetchDeals()
            let (a, d) = try await (apps, dealData)
            // Animate the section reveal so cards slide/settle in with the
            // same motion language as the rest of the app instead of popping.
            withAnimation(.whisperSmooth) {
                applications = a.asBrand
                deals = d.deals
                payments = d.payments
                trackedPosts = d.posts
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Respond sheet (brand)

/// The brand's decision form: accept as-is, counter with edited terms (an
/// easily editable form, mirroring the featured-profile editor pattern), or
/// deny (which also blocks the brand from DMing the creator).
struct WhisperSponsorRespondSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let application: WhisperSponsorApplication
    var onResponded: () -> Void = {}

    @State private var basis: WhisperSponsorBasis = .perPost
    @State private var amountString: String = ""
    @State private var notes: String = ""
    @State private var deliverables: String = ""
    @State private var exclusive: Bool = false
    @State private var expiresInDays: Int = 0
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var confirmDeny: Bool = false

    private var accent: Color { WhisperTheme.ink(colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        creatorSummary

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Terms")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text("Accept as-is, or edit and send back as a counter-offer.")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Picker("Basis", selection: $basis) {
                                ForEach(WhisperSponsorBasis.allCases) { b in
                                    Text(b.displayName).tag(b)
                                }
                            }
                            .pickerStyle(.segmented)
                            HStack(spacing: 4) {
                                Text("$")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                TextField("250", text: $amountString)
                                    .font(.title3.weight(.bold))
                                    .keyboardType(.decimalPad)
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text(basis.shortLabel)
                                    .font(.footnote)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            .padding(14)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                            TextField("Deliverables brief — e.g. 2 feed posts + 1 story, product visible, tag your brand…", text: $deliverables, axis: .vertical)
                                .lineLimit(2...5)
                                .font(.subheadline)
                                .padding(14)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            TextField("Other notes — timelines, usage rights…", text: $notes, axis: .vertical)
                                .lineLimit(2...5)
                                .font(.subheadline)
                                .padding(14)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            Toggle(isOn: $exclusive) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Exclusivity clause")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    Text("The creator can't promote competing brands during the deal.")
                                        .font(.caption2)
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                            }
                            .tint(accent)
                            .padding(.vertical, 2)
                            Picker("Counter-offer deadline", selection: $expiresInDays) {
                                Text("No offer deadline").tag(0)
                                Text("Expires in 3 days").tag(3)
                                Text("Expires in 7 days").tag(7)
                                Text("Expires in 14 days").tag(14)
                            }
                            .pickerStyle(.menu)
                            .tint(WhisperTheme.ink(colorScheme))
                        }

                        VStack(spacing: 10) {
                            Button {
                                Haptics.tap()
                                Task { await respond("accept") }
                            } label: {
                                HStack(spacing: 8) {
                                    if isSubmitting {
                                        ProgressView().tint(WhisperTheme.surface(colorScheme))
                                    }
                                    Text("Accept & create deal")
                                }
                                .font(.body.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(WhisperTheme.ink(colorScheme), in: Capsule())
                                .foregroundStyle(WhisperTheme.surface(colorScheme))
                            }
                            .buttonStyle(.plain)

                            Button {
                                Haptics.tap()
                                Task { await respond("counter") }
                            } label: {
                                Text("Send counter-offer")
                                    .font(.body.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .overlay {
                                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)

                            Button {
                                Haptics.warning()
                                confirmDeny = true
                            } label: {
                                Text("Deny application")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(.red)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        .disabled(isSubmitting)

                        Text("Denying permanently blocks your brand from DMing @\(application.creatorUsername ?? "this creator") — this protects creators from off-platform pressure.")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))

                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Respond")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .alert("Deny this application?", isPresented: $confirmDeny) {
                Button("Deny", role: .destructive) {
                    Task { await respond("deny") }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("@\(application.creatorUsername ?? "The creator") won't be able to receive DMs from your brand afterward.")
            }
        }
        .onAppear {
            basis = WhisperSponsorBasis(rawValue: application.termsBasis ?? application.desiredBasis) ?? .perPost
            let cents = application.termsAmountCents ?? application.desiredAmountCents
            amountString = cents % 100 == 0 ? String(cents / 100) : String(format: "%.2f", Double(cents) / 100)
            notes = application.termsNotes ?? ""
            deliverables = application.termsDeliverables ?? ""
            exclusive = application.termsExclusive
        }
    }

    private var creatorSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WhisperAvatar(username: application.creatorUsername ?? "creator", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(application.creatorUsername ?? "creator")")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let followers = application.creatorFollowers {
                            Text("\(followers.formatted()) followers")
                        }
                        if application.creatorFollowers != nil && application.creatorAge != nil {
                            Text("·")
                        }
                        if let age = application.creatorAge {
                            Text("\(age) yrs")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer(minLength: 0)
                WhisperSponsorStatusPill(status: application.status)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sponsorAmountText(application.desiredAmountCents, application.desiredBasis))
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Requested rate")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            if let message = application.message, !message.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WhisperTheme.hairline(colorScheme))
                        .frame(width: 3)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineSpacing(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func respond(_ action: String) async {
        var cents: Int?
        if action != "deny" {
            let cleaned = amountString
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let dollars = Double(cleaned), dollars >= 1 else {
                errorMessage = "Enter a valid amount."
                return
            }
            cents = Int((dollars * 100).rounded())
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await WhisperBrandService.shared.respond(
                applicationId: application.id,
                action: action,
                termsBasis: action == "deny" ? nil : basis,
                termsAmountCents: cents,
                termsNotes: action == "deny" ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
                termsDeliverables: action == "deny" ? nil : deliverables.trimmingCharacters(in: .whitespacesAndNewlines),
                termsExclusive: action == "deny" ? nil : exclusive,
                expiresInDays: action == "counter" ? expiresInDays : nil
            )
            Haptics.success()
            onResponded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
