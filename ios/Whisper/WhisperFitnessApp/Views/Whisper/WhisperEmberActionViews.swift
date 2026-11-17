import SwiftUI

// MARK: - Action row

/// Tappable action buttons rendered under an Jasper reply — each one executes
/// a real app capability through `WhisperEmberActionRouter`.
struct WhisperEmberActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let actions: [WhisperEmberAction]
    /// Meeting-box styling (white-on-glass) instead of theme cards.
    var forceDark: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { action in
                Button {
                    Haptics.tap()
                    WhisperEmberActionRouter.shared.perform(action)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: action.iconName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(iconColor)
                            .frame(width: 24, height: 24)
                            .background(iconBackground, in: Circle())
                        Text(action.displayLabel)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(textColor)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(mutedColor)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .frame(height: 42)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rowBackground, in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(strokeColor, lineWidth: 1)
                    }
                    .contentShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var textColor: Color {
        forceDark ? .white.opacity(0.92) : WhisperTheme.ink(colorScheme)
    }
    private var mutedColor: Color {
        forceDark ? .white.opacity(0.4) : WhisperTheme.muted(colorScheme)
    }
    private var iconColor: Color {
        forceDark ? .black : WhisperTheme.surface(colorScheme)
    }
    private var iconBackground: Color {
        forceDark ? .white.opacity(0.92) : WhisperTheme.ink(colorScheme)
    }
    private var rowBackground: Color {
        forceDark ? .white.opacity(0.08) : WhisperTheme.card(colorScheme)
    }
    private var strokeColor: Color {
        forceDark ? .white.opacity(0.12) : WhisperTheme.hairline(colorScheme)
    }
}

// MARK: - Modal host

extension View {
    /// Attach once per Jasper surface — renders the router's self-produced
    /// modal as a bottom card overlay (safe inside sheets and covers).
    func emberActionModals() -> some View {
        modifier(WhisperEmberActionModalHost())
    }
}

struct WhisperEmberActionModalHost: ViewModifier {
    @State private var router = WhisperEmberActionRouter.shared

    func body(content: Content) -> some View {
        content.overlay {
            ZStack(alignment: .bottom) {
                if let modal = router.modal {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { router.dismissModal() }
                        .transition(.opacity)
                    WhisperEmberModalCard(modal: modal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: router.modal)
        }
    }
}

/// Switches the presented modal kind into its card.
private struct WhisperEmberModalCard: View {
    let modal: WhisperEmberModal

    var body: some View {
        Group {
            switch modal {
            case .call(let username, let video):
                WhisperEmberCallModalCard(username: username, preferVideo: video)
            case .schedule(let title, let when, let invite):
                WhisperEmberScheduleModalCard(initialTitle: title, initialWhen: when, invite: invite)
            case .reply(let username, let text):
                WhisperEmberReplyModalCard(username: username, initialText: text)
            case .plan(let draft):
                WhisperEmberPlanModalCard(draft: draft)
            case .bioAge(let username):
                WhisperBioAgeModalCard(username: username)
            case .dietPlan(let username):
                JasperConnectGlowModalCard {
                    if let client = WhisperEmberActionRouter.jasperClient(for: username) {
                        JasperDietPlanSheet(
                            source: .coachClient(uid: client.uid, username: client.username),
                            onClose: { WhisperEmberActionRouter.shared.dismissModal() }
                        )
                    } else {
                        JasperDietPlanSheet(
                            source: .ownConnect,
                            onClose: { WhisperEmberActionRouter.shared.dismissModal() }
                        )
                    }
                }
            case .groceries(let username):
                JasperConnectGlowModalCard {
                    if let client = WhisperEmberActionRouter.jasperClient(for: username) {
                        JasperGroceryListSheet(
                            source: .coachClient(uid: client.uid, username: client.username),
                            onClose: { WhisperEmberActionRouter.shared.dismissModal() }
                        )
                    } else {
                        JasperGroceryListSheet(
                            source: .ownConnect,
                            onClose: { WhisperEmberActionRouter.shared.dismissModal() }
                        )
                    }
                }
            case .clientDashboard(let username):
                JasperConnectGlowModalCard {
                    JasperClientPulseModalCard(username: username)
                }
            case .marketplace(let query):
                JasperConnectGlowModalCard {
                    JasperMarketplaceSheet(
                        initialQuery: query ?? "",
                        onClose: { WhisperEmberActionRouter.shared.dismissModal() }
                    )
                }
            case .recipeSave(let draft):
                JasperConnectGlowModalCard {
                    JasperRecipesSheet(
                        initialDraft: draft,
                        onClose: { WhisperEmberActionRouter.shared.dismissModal() }
                    )
                }
            case .waterTracker:
                JasperConnectGlowModalCard {
                    JasperWaterTrackerSheet(
                        onClose: { WhisperEmberActionRouter.shared.dismissModal() }
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// Tall glow-card wrapper for Jasper Connect sheets (diet plan, groceries)
/// presented through the action modal host — the full sheet experience,
/// clipped to a card so it sits on the dimmer like every other Jasper modal.
private struct JasperConnectGlowModalCard<Inner: View>: View {
    @ViewBuilder let inner: Inner

    var body: some View {
        inner
            .frame(maxWidth: 440)
            .frame(maxHeight: 620)
            .clipShape(.rect(cornerRadius: 28))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
    }
}

// MARK: - Shared modal chrome

private struct EmberModalShell<Inner: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let heading: String
    @ViewBuilder let inner: Inner

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                WhisperEmberMascot(
                    size: 26,
                    expression: .attentive,
                    coachMode: WhisperEmberCoachMode.load(),
                    usesIntelligenceStyle: true
                )
                .frame(width: 26, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("KNOT")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Text(heading)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    WhisperEmberActionRouter.shared.dismissModal()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(WhisperTheme.surface(colorScheme), in: Circle())
                        .overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            inner
        }
        .padding(16)
        .frame(maxWidth: 440)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
    }
}

private struct EmberModalPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String
    var working: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                if working {
                    ProgressView()
                        .controlSize(.small)
                        .tint(WhisperTheme.surface(colorScheme))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                disabled ? WhisperTheme.ink(colorScheme).opacity(0.35) : WhisperTheme.ink(colorScheme),
                in: Capsule()
            )
            .foregroundStyle(WhisperTheme.surface(colorScheme))
        }
        .buttonStyle(.plain)
        .disabled(disabled || working)
    }
}

private struct EmberModalErrorLine: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EmberModalSuccessHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.green)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Call modal

struct WhisperEmberCallModalCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let username: String
    let preferVideo: Bool

    @State private var working: Bool = false
    @State private var errorText: String?

    var body: some View {
        EmberModalShell(icon: "phone.fill", heading: "Start a call") {
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    WhisperAvatar(username: username, size: 64)
                    Text("@\(username)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Knot will place a real Whisper call.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .frame(maxWidth: .infinity)

                if let errorText {
                    EmberModalErrorLine(message: errorText)
                }

                HStack(spacing: 10) {
                    callButton(title: "Audio", icon: "phone.fill", video: false, prominent: !preferVideo)
                    callButton(title: "Video", icon: "video.fill", video: true, prominent: preferVideo)
                }
            }
        }
    }

    private func callButton(title: String, icon: String, video: Bool, prominent: Bool) -> some View {
        Button {
            Haptics.tap()
            guard !working else { return }
            working = true
            errorText = nil
            Task {
                let error = await WhisperEmberActionRouter.shared.startCall(username: username, video: video)
                working = false
                if let error {
                    errorText = error
                } else {
                    WhisperEmberActionRouter.shared.dismissModal()
                }
            }
        } label: {
            HStack(spacing: 7) {
                if working {
                    ProgressView()
                        .controlSize(.small)
                        .tint(prominent ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                }
                Text(title)
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                prominent
                    ? AnyShapeStyle(WhisperTheme.ink(colorScheme))
                    : AnyShapeStyle(WhisperTheme.surface(colorScheme)),
                in: Capsule()
            )
            .foregroundStyle(prominent ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(working)
    }
}

// MARK: - Schedule modal

struct WhisperEmberScheduleModalCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let invite: String?

    @State private var title: String
    @State private var scheduleLater: Bool
    @State private var date: Date
    @State private var includeInvite: Bool
    @State private var working: Bool = false
    @State private var errorText: String?
    @State private var created: WhisperMeetingRow?
    @State private var invitedOK: Bool = false

    init(initialTitle: String, initialWhen: Date?, invite: String?) {
        self.invite = invite
        _title = State(initialValue: initialTitle)
        _scheduleLater = State(initialValue: initialWhen != nil)
        _date = State(initialValue: initialWhen ?? Date().addingTimeInterval(3600))
        _includeInvite = State(initialValue: invite != nil)
    }

    var body: some View {
        EmberModalShell(icon: "calendar.badge.plus", heading: "Schedule a meeting") {
            if let created {
                successBody(created)
            } else {
                formBody
            }
        }
    }

    @ViewBuilder
    private var formBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Meeting title", text: $title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }

            Toggle(isOn: $scheduleLater) {
                Text("Schedule for later")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .tint(WhisperTheme.ink(colorScheme))

            if scheduleLater {
                DatePicker(
                    "When",
                    selection: $date,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline)
                .tint(WhisperTheme.ink(colorScheme))
            }

            if let invite {
                Toggle(isOn: $includeInvite) {
                    HStack(spacing: 8) {
                        WhisperAvatar(username: invite, size: 24)
                        Text("Send invite to @\(invite)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
                .tint(WhisperTheme.ink(colorScheme))
            }

            if let errorText {
                EmberModalErrorLine(message: errorText)
            }

            EmberModalPrimaryButton(
                title: scheduleLater ? "Create scheduled meeting" : "Create meeting",
                icon: "calendar.badge.plus",
                working: working,
                disabled: title.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                create()
            }
        }
    }

    @ViewBuilder
    private func successBody(_ row: WhisperMeetingRow) -> some View {
        VStack(spacing: 12) {
            EmberModalSuccessHeader(
                title: "Meeting created",
                subtitle: scheduleLater
                    ? date.formatted(date: .abbreviated, time: .shortened)
                    + (includeInvite && invite != nil && invitedOK ? " · invite sent to @\(invite ?? "")" : "")
                    : "Ready now" + (includeInvite && invite != nil && invitedOK ? " · invite sent to @\(invite ?? "")" : "")
            )
            EmberModalPrimaryButton(title: "Open Meetings", icon: "arrow.up.right", working: false) {
                WhisperEmberActionRouter.shared.dismissModal()
                WhisperEmberActionRouter.shared.navigate(route: "meetings")
            }
            Button {
                WhisperEmberActionRouter.shared.dismissModal()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .buttonStyle(.plain)
        }
    }

    private func create() {
        guard !working else { return }
        working = true
        errorText = nil
        let when: Date? = scheduleLater ? date : nil
        let meetingTitle = title
        Task {
            let (row, error) = await WhisperEmberActionRouter.shared.scheduleMeeting(title: meetingTitle, at: when)
            if let row {
                if includeInvite, let invite {
                    let whenText = when.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "starting soon"
                    let body = "\u{1F4C5} \(meetingTitle) — \(whenText). I set this up in Whisper Meetings — join from the Meetings tab when it starts."
                    invitedOK = await WhisperEmberActionRouter.shared.sendDirectMessage(to: invite, body: body) == nil
                }
                Haptics.success()
                withAnimation(.spring(response: 0.32)) { created = row }
            } else {
                errorText = error ?? "Couldn't create the meeting."
            }
            working = false
        }
    }
}

// MARK: - Reply modal

struct WhisperEmberReplyModalCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let username: String

    @State private var text: String
    @State private var working: Bool = false
    @State private var errorText: String?
    @State private var sent: Bool = false
    @FocusState private var focused: Bool

    init(username: String, initialText: String) {
        self.username = username
        _text = State(initialValue: initialText)
    }

    var body: some View {
        EmberModalShell(icon: "paperplane.fill", heading: "Message @\(username)") {
            if sent {
                VStack(spacing: 12) {
                    EmberModalSuccessHeader(title: "Sent to @\(username)", subtitle: nil)
                    EmberModalPrimaryButton(title: "Open chat", icon: "arrow.up.right", working: false) {
                        WhisperEmberActionRouter.shared.dismissModal()
                        WhisperEmberActionRouter.shared.navigate(route: "dm", arg: username)
                    }
                    Button {
                        WhisperEmberActionRouter.shared.dismissModal()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Knot drafted this — edit anything before it sends.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))

                    TextEditor(text: $text)
                        .font(.subheadline)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 110, maxHeight: 200)
                        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }

                    if let errorText {
                        EmberModalErrorLine(message: errorText)
                    }

                    EmberModalPrimaryButton(
                        title: "Send to @\(username)",
                        icon: "paperplane.fill",
                        working: working,
                        disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        send()
                    }
                }
            }
        }
    }

    private func send() {
        guard !working else { return }
        working = true
        errorText = nil
        focused = false
        let body = text
        Task {
            let error = await WhisperEmberActionRouter.shared.sendDirectMessage(to: username, body: body)
            working = false
            if let error {
                errorText = error
            } else {
                Haptics.success()
                withAnimation(.spring(response: 0.32)) { sent = true }
            }
        }
    }
}

// MARK: - Plan modal

struct WhisperEmberPlanModalCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let draft: WhisperEmberPlanDraft

    @State private var saving: Bool = false
    @State private var saved: Bool = false
    @State private var sending: Bool = false
    @State private var sentToClient: Bool = false
    @State private var errorText: String?

    var body: some View {
        EmberModalShell(icon: "list.clipboard.fill", heading: draft.title) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    if let client = draft.client {
                        chip("@\(client)", icon: "person.fill")
                    }
                    chip("\(draft.weeks) wks", icon: "calendar")
                    chip("\(draft.sessionsPerWeek)x / wk", icon: "figure.strengthtraining.traditional")
                }
                if !draft.focus.isEmpty {
                    Text(draft.focus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                if !draft.summary.isEmpty {
                    Text(draft.summary)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !draft.days.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(draft.days.enumerated()), id: \.offset) { _, day in
                                dayRow(day)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }

                if let errorText {
                    EmberModalErrorLine(message: errorText)
                }

                EmberModalPrimaryButton(
                    title: saved ? "Saved to Programs" : "Save to Programs",
                    icon: saved ? "checkmark" : "tray.and.arrow.down.fill",
                    working: saving,
                    disabled: saved
                ) {
                    save()
                }

                if let client = draft.client {
                    Button {
                        Haptics.tap()
                        sendToClient(client)
                    } label: {
                        HStack(spacing: 7) {
                            if sending {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(WhisperTheme.ink(colorScheme))
                            } else {
                                Image(systemName: sentToClient ? "checkmark" : "paperplane")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(sentToClient ? "Sent to @\(client)" : "Send to @\(client)")
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || sentToClient)
                }
            }
        }
    }

    private func chip(_ label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(WhisperTheme.surface(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
    }

    private func dayRow(_ day: WhisperEmberAction.PlanDay) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(day.name)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if let focus = day.focus, !focus.isEmpty {
                    Text(focus)
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            ForEach(Array((day.exercises ?? []).enumerated()), id: \.offset) { _, ex in
                HStack(spacing: 6) {
                    Circle()
                        .fill(WhisperTheme.muted(colorScheme))
                        .frame(width: 3, height: 3)
                    Text(ex.name)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Spacer(minLength: 0)
                    if let sets = ex.sets {
                        Text("\(sets) × \(ex.reps ?? "8-12")")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.surface(colorScheme).opacity(0.6), in: .rect(cornerRadius: 12))
    }

    private func save() {
        guard !saving, !saved else { return }
        saving = true
        errorText = nil
        Task {
            let ok = await WhisperEmberActionRouter.shared.savePlan(draft)
            saving = false
            if ok {
                Haptics.success()
                withAnimation(.spring(response: 0.3)) { saved = true }
            } else {
                errorText = "Couldn't save the program — try again."
            }
        }
    }

    private func sendToClient(_ client: String) {
        guard !sending, !sentToClient else { return }
        sending = true
        errorText = nil
        Task {
            let error = await WhisperEmberActionRouter.shared.sendDirectMessage(
                to: client,
                body: draft.asMessageText()
            )
            sending = false
            if let error {
                errorText = error
            } else {
                Haptics.success()
                withAnimation(.spring(response: 0.3)) { sentToClient = true }
            }
        }
    }
}

// MARK: - Route destination sheet

/// Identifiable wrapper for the generic Jasper route sheet in `WhisperRootView`.
struct WhisperEmberRouteSheet: Identifiable, Hashable {
    let id: String
}

/// Presents any atlas sheet route as a real destination view. Routes whose
/// destination already contains its own `NavigationStack` are presented bare.
struct WhisperEmberRouteSheetView: View {
    let route: String

    /// Routes this view can present. Keep in sync with `WhisperEmberAtlas`.
    static let supported: Set<String> = [
        "meetings", "meeting_sidekick", "calendar", "settings", "edit_profile",
        "notification_settings", "security", "blocked", "verification",
        "coach_clients", "coach_programs", "my_coaches", "recruiter",
        "creator_dashboard", "studio", "communities", "live_rooms",
        "brands", "sponsorships", "recipes", "water",
    ]

    var body: some View {
        switch route {
        case "meetings": WhisperMeetingsView()
        case "meeting_sidekick": WhisperMeetingNotesListView().id(AccountStorage.currentUserID)
        case "calendar": WhisperCalendarView()
        case "settings": WhisperSettingsView()
        case "edit_profile": WhisperEditProfileView()
        case "notification_settings": NavigationStack { WhisperNotificationSettingsView() }
        case "security": WhisperSecurityCenterView()
        case "blocked": NavigationStack { WhisperBlockedAccountsView() }
        case "verification": WhisperVerificationApplicationView()
        case "coach_clients": WhisperCoachClientsView()
        case "coach_programs": WhisperCoachProgramsView()
        case "recipes": JasperRecipesSheet()
        case "water": JasperWaterTrackerSheet()
        case "my_coaches": WhisperMyCoachesView()
        case "recruiter": WhisperRecruiterDashboardView()
        case "creator_dashboard": WhisperCreatorDashboardView()
        case "studio": WhisperStudioView()
        case "communities": NavigationStack { WhisperCommunitiesView() }
        case "live_rooms": WhisperLiveRoomsListView()
        case "brands": WhisperBrandDirectoryView()
        case "sponsorships": WhisperMySponsorshipsView()
        default:
            WhisperEmptyState(
                icon: "questionmark.circle",
                title: "Not available",
                message: "This destination isn't reachable yet."
            )
        }
    }
}
