import SwiftUI

/// "Coach access" sheet — the `coach_grants` permission layer, kept deliberately
/// separate from "Connect Whisper" (identity) because they answer different
/// questions. Two roles in one place:
///
/// - **As a client:** every coach who has accepted you appears here — pick the
///   permission level (view only, or view & edit) and authorize with ONE tap.
///   No codes, nothing to paste. Change the level or revoke anytime.
/// - **As a coach:** see which clients have authorized you, nudge the ones who
///   haven't yet with a DM, and drop access you no longer need.
struct WhisperCoachAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var grants = WhisperCoachGrantService.shared
    @State private var role: Role = .client

    enum Role: String, CaseIterable {
        case client = "My coaches"
        case coach = "My clients"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        rolePicker
                        if role == .client {
                            ClientCoachAccessSection(grants: grants)
                        } else {
                            CoachClientsSection(grants: grants)
                        }
                        if let msg = grants.statusMessage {
                            Text(msg)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .animation(.easeInOut(duration: 0.2), value: grants.statusMessage)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: role)
                }
            }
            .whisperNavigationBack()
            .navigationTitle("Coach access")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refreshAll() }
            .whisperRefreshable { await refreshAll() }
        }
    }

    /// Grants + the coaching roster load together: the authorize list is the
    /// accepted-coaches roster minus whoever already holds a grant.
    private func refreshAll() async {
        async let g: Void = grants.refresh()
        async let r: Void = WhisperCoachRequestService.shared.refresh()
        _ = await (g, r)
    }

    private var rolePicker: some View {
        Picker("Role", selection: $role) {
            ForEach(Role.allCases, id: \.self) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: role) { _, _ in
            Haptics.tap()
            grants.statusMessage = nil
        }
    }
}

// MARK: - Client side

/// Where a user authorizes their coaches with one tap and manages existing
/// grants. No codes anywhere — the backend verifies the accepted coaching
/// relationship and writes the grant directly.
private struct ClientCoachAccessSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var grants: WhisperCoachGrantService

    @State private var requests = WhisperCoachRequestService.shared
    @State private var toRevoke: WhisperCoachGrantService.CoachGrantParty?
    @State private var confirmRevokeAll: Bool = false

    /// Accepted coaches who don't hold an active grant yet — the one-tap list.
    private var awaitingAuthorization: [WhisperCoachRequestRow] {
        let granted = Set(grants.coaches.map { $0.uid.lowercased() })
        return requests.myCoaches.filter { !granted.contains($0.coach_user_id.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 18) {
            header(
                icon: "person.badge.shield.checkmark",
                title: "Let a coach see your progress",
                subtitle: "Authorize your coach in one tap — no codes. You choose whether they can just view or also edit, and you can change or revoke it anytime."
            )

            if !awaitingAuthorization.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AWAITING YOUR AUTHORIZATION")
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    ForEach(awaitingAuthorization) { row in
                        CoachAuthorizeCard(grants: grants, coach: row)
                    }
                }
            }

            if grants.coaches.isEmpty && awaitingAuthorization.isEmpty {
                emptyState(
                    icon: "person.fill.questionmark",
                    title: "No coaches yet",
                    message: "When a coach accepts your coaching request, they'll appear here — authorize them with a single tap."
                )
            } else if !grants.coaches.isEmpty {
                grantList
            }
        }
        .confirmationDialog(
            "Disconnect this coach?",
            isPresented: Binding(get: { toRevoke != nil }, set: { if !$0 { toRevoke = nil } }),
            titleVisibility: .visible,
            presenting: toRevoke
        ) { party in
            Button("Disconnect", role: .destructive) {
                Task { await grants.revoke(otherUID: party.uid); toRevoke = nil }
            }
            Button("Cancel", role: .cancel) { toRevoke = nil }
        } message: { party in
            Text("@\(party.username ?? shortUID(party.uid)) will lose access to your fitness data.")
        }
        .confirmationDialog(
            "Remove all coaches?",
            isPresented: $confirmRevokeAll,
            titleVisibility: .visible
        ) {
            Button("Remove all", role: .destructive) {
                Task { await grants.revokeAllCoaches() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every coach will lose access to your fitness data. You can re-authorize anytime.")
        }
    }

    private var grantList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CONNECTED COACHES")
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer()
                Button {
                    Haptics.warning()
                    confirmRevokeAll = true
                } label: {
                    Text("Remove all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            ForEach(grants.coaches) { party in
                CoachGrantRow(
                    party: party,
                    actionLabel: "Disconnect",
                    onSwitchScope: { newScope in
                        Task { await grants.authorize(coachUID: party.uid, scope: newScope) }
                    },
                    action: { toRevoke = party }
                )
            }
        }
    }

    private func header(icon: String, title: String, subtitle: String) -> some View {
        coachAccessHeader(icon: icon, title: title, subtitle: subtitle, colorScheme: colorScheme)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        coachAccessEmpty(icon: icon, title: title, message: message, colorScheme: colorScheme)
    }
}

/// One accepted coach awaiting authorization: permission picker + a single
/// Authorize button. On success the card disappears on its own — the coach
/// moves into the connected list.
private struct CoachAuthorizeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var grants: WhisperCoachGrantService
    let coach: WhisperCoachRequestRow

    @State private var scope: WhisperCoachGrantService.GrantScope = .readWrite
    @State private var isAuthorizing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WhisperAvatar(username: coach.coach_username, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("@\(coach.coach_username)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Your coach")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
            }

            Picker("Access level", selection: $scope) {
                Text("View only").tag(WhisperCoachGrantService.GrantScope.read)
                Text("View & edit").tag(WhisperCoachGrantService.GrantScope.readWrite)
            }
            .pickerStyle(.segmented)
            .onChange(of: scope) { _, _ in Haptics.tap() }

            Text(scope == .read
                 ? "They can view your workouts, meals, sleep, weight, and progress — never your blood work or photo files."
                 : "They can view your data and coach you inside Jasper — assign programs, log corrections. Never your blood work or photo files.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard !isAuthorizing else { return }
                Haptics.tap()
                grants.statusMessage = nil
                isAuthorizing = true
                Task {
                    _ = await grants.authorize(coachUID: coach.coach_user_id, scope: scope)
                    isAuthorizing = false
                }
            } label: {
                HStack(spacing: 10) {
                    if isAuthorizing {
                        ProgressView().tint(WhisperTheme.surface(colorScheme))
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                    }
                    Text("Authorize @\(coach.coach_username)")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isAuthorizing)
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

// MARK: - Coach side

/// Where a coach sees who has authorized them and nudges clients who haven't.
/// Coaches can't grant themselves access — the client authorizes from their
/// side with one tap, so all this side can do is ask.
private struct CoachClientsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var grants: WhisperCoachGrantService

    @State private var requests = WhisperCoachRequestService.shared
    @State private var toRevoke: WhisperCoachGrantService.CoachGrantParty?
    @State private var askedUIDs: Set<String> = []

    /// Accepted clients who haven't authorized data access yet.
    private var awaitingClients: [WhisperCoachRequestRow] {
        let granted = Set(grants.clients.map { $0.uid.lowercased() })
        return requests.myClients.filter { !granted.contains($0.client_user_id.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 18) {
            header(
                icon: "person.2.badge.gearshape",
                title: "Your clients' data access",
                subtitle: "Clients authorize you from their side — one tap in their Coach access, no codes. Once they do, their live Jasper data opens in your client dashboard."
            )

            if !awaitingClients.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AWAITING AUTHORIZATION")
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    ForEach(awaitingClients) { row in
                        awaitingRow(row)
                    }
                }
            }

            if grants.clients.isEmpty && awaitingClients.isEmpty {
                emptyState(
                    icon: "person.3.sequence",
                    title: "No clients yet",
                    message: "When someone hires you as their coach, they'll appear here. Access opens the moment they tap Authorize on their side."
                )
            } else if !grants.clients.isEmpty {
                clientList
            }
        }
        .confirmationDialog(
            "Remove this client?",
            isPresented: Binding(get: { toRevoke != nil }, set: { if !$0 { toRevoke = nil } }),
            titleVisibility: .visible,
            presenting: toRevoke
        ) { party in
            Button("Remove", role: .destructive) {
                Task { await grants.revoke(otherUID: party.uid); toRevoke = nil }
            }
            Button("Cancel", role: .cancel) { toRevoke = nil }
        } message: { party in
            Text("You'll lose access to @\(party.username ?? shortUID(party.uid))'s fitness data.")
        }
    }

    /// One accepted-but-unauthorized client, with a DM nudge that walks them
    /// to the one-tap Authorize button on their side.
    private func awaitingRow(_ row: WhisperCoachRequestRow) -> some View {
        let asked = askedUIDs.contains(row.client_user_id)
        return HStack(spacing: 12) {
            WhisperAvatar(username: row.client_username, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("@\(row.client_username)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Hasn't authorized access yet")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Button {
                Haptics.tap()
                askedUIDs.insert(row.client_user_id)
                grants.statusMessage = "Asked @\(row.client_username) to authorize you."
                Task {
                    _ = await WhisperBackendService.shared.sendMessage(
                        toUserID: row.client_user_id,
                        toUsername: row.client_username,
                        body: "Quick one — could you authorize my coach access? In Whisper: Settings \u{2192} Sync with Jasper \u{2192} Coach access, then tap Authorize next to my name. One tap, you pick view-only or view & edit, and you can revoke anytime."
                    )
                }
            } label: {
                Text(asked ? "Asked" : "Ask to authorize")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(asked ? WhisperTheme.muted(colorScheme) : WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        asked ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme),
                        in: .capsule
                    )
                    .overlay {
                        if asked {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(asked)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var clientList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR CLIENTS")
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            ForEach(grants.clients) { party in
                CoachGrantRow(party: party, actionLabel: "Remove") { toRevoke = party }
            }
        }
    }

    private func header(icon: String, title: String, subtitle: String) -> some View {
        coachAccessHeader(icon: icon, title: title, subtitle: subtitle, colorScheme: colorScheme)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        coachAccessEmpty(icon: icon, title: title, message: message, colorScheme: colorScheme)
    }
}

// MARK: - Shared row

/// One grant row showing the other party, the scope they hold, and actions via
/// an overflow menu. Client-side rows also offer a one-tap scope switch.
private struct CoachGrantRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let party: WhisperCoachGrantService.CoachGrantParty
    let actionLabel: String
    var onSwitchScope: ((WhisperCoachGrantService.GrantScope) -> Void)? = nil
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: party.username ?? "?", size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("@\(party.username ?? shortUID(party.uid))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                HStack(spacing: 6) {
                    Image(systemName: party.scope == .readWrite ? "pencil.circle.fill" : "eye.circle.fill")
                        .font(.caption)
                    Text(party.scope.label)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.coachAccent)
            }
            Spacer()
            Menu {
                if let onSwitchScope {
                    if party.scope == .readWrite {
                        Button {
                            onSwitchScope(.read)
                        } label: {
                            Label("Switch to view only", systemImage: "eye")
                        }
                    } else {
                        Button {
                            onSwitchScope(.readWrite)
                        } label: {
                            Label("Allow view & edit", systemImage: "pencil")
                        }
                    }
                }
                Button(role: .destructive, action: action) {
                    Label(actionLabel, systemImage: "xmark.shield")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

// MARK: - Shared helpers

private func shortUID(_ uid: String) -> String {
    String(uid.prefix(6))
}

private func coachAccessHeader(icon: String, title: String, subtitle: String, colorScheme: ColorScheme) -> some View {
    VStack(spacing: 12) {
        ZStack {
            Circle()
                .fill(WhisperTheme.card(colorScheme))
                .frame(width: 72, height: 72)
                .overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(WhisperTheme.coachAccent)
        }
        Text(title)
            .font(.title3.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(WhisperTheme.ink(colorScheme))
        Text(subtitle)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 8)
    }
    .padding(.top, 4)
}

private func coachAccessEmpty(icon: String, title: String, message: String, colorScheme: ColorScheme) -> some View {
    VStack(spacing: 10) {
        WhisperMeetDoodle(symbol: icon, height: 120)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WhisperTheme.ink(colorScheme))
        Text(message)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 24)
    }
    .padding(.top, 12)
}
