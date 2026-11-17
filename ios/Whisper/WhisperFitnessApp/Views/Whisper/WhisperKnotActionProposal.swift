import SwiftUI
import UserNotifications

/// Approval is local UI state, never something the model can grant itself.
nonisolated struct WhisperKnotActionProposal: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case post, meeting, reminder, community, follow, tool }
    enum State: String, Codable, Sendable { case pending, running, denied, completed, unavailable, unconfirmed, expired }
    struct Request: Decodable, Sendable {
        let kind: String
        var title: String?
        var text: String?
        var when: String?
        var community: String?
    }
    var id = UUID()
    let kind: Kind
    var text: String = ""
    var target: String = ""
    var date: Date?
    var action: WhisperEmberAction?
    var state: State = .pending
    var result: String?
    var postID: String?
    var reminderID: String?
    var originalRequest: String?

    var needsDetails: Bool {
        switch kind {
        case .post: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .meeting, .reminder: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || date == nil
        case .follow: target.isEmpty
        case .community: Self.community(target) == nil
        case .tool:
            action?.kind != .schedule || action?.invite?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || date == nil
        }
    }

    /// A review surface only, never an inferred write or guessed date/content.
    /// Anchored commands exclude general capability questions and quoted prose.
    static func reviewFallback(for message: String) -> Self? {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 4000 else { return nil }
        func matches(_ pattern: String) -> Bool { value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if matches("^(please )?remind me (to|about|at|on|tomorrow)\\b") {
            return Self(kind: .reminder, originalRequest: value)
        }
        if matches("^(please )?(schedule|create|set up) (a |my )?(meeting|meet)\\b") {
            return Self(kind: .meeting, originalRequest: value)
        }
        if matches("^(please )?(publish|post)\\s+[\"“]") {
            let quotes = CharacterSet(charactersIn: "\"“”")
            if let start = value.rangeOfCharacter(from: quotes), let end = value.rangeOfCharacter(from: quotes, options: .backwards), start.upperBound < end.lowerBound,
               value[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Self(kind: .post, text: String(value[start.upperBound..<end.lowerBound]))
            }
        }
        if matches("^(please )?follow @[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*!?$"), let at = value.firstIndex(of: "@") {
            let target = String(value[value.index(after: at)...]).trimmingCharacters(in: CharacterSet(charactersIn: "!"))
            return Self(kind: .follow, target: target)
        }
        if matches("^(please )?join ") {
            let name = value.replacingOccurrences(of: "^(please )?join ", with: "", options: [.regularExpression, .caseInsensitive])
            if let community = community(name) { return Self(kind: .community, target: community.id) }
        }
        return nil
    }

    static func proposals(actions: [WhisperEmberAction], requests: [Request]) -> [Self] {
        var values: [Self] = []
        for request in requests.prefix(4) {
            switch request.kind {
            case "reminder":
                values.append(Self(kind: .reminder, text: request.title ?? request.text ?? "", date: WhisperEmberActionParser.parseWhen(request.when)))
            case "joinCommunity":
                if let community = community(request.community) {
                    values.append(Self(kind: .community, target: community.id))
                }
            default: break
            }
        }
        for action in actions.prefix(4) {
            switch action.kind {
            case .post:
                values.append(Self(kind: .post, text: action.text ?? "", target: action.community ?? ""))
            case .schedule:
                // Invitations need the existing recipient review, not an implied send.
                if action.invite?.isEmpty == false {
                    guard let title = action.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          action.invite?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                          let date = WhisperEmberActionParser.parseWhen(action.whenISO) else { continue }
                    values.append(Self(kind: .tool, text: title, target: action.invite ?? "", date: date, action: action))
                } else {
                    values.append(Self(kind: .meeting, text: action.title ?? "", date: WhisperEmberActionParser.parseWhen(action.whenISO)))
                }
            case .follow:
                if let community = community(action.community) {
                    values.append(Self(kind: .community, target: community.id))
                } else {
                    values.append(Self(kind: .follow, target: WhisperEmberAction.cleanUsername(action.username ?? action.client ?? "")))
                }
            default:
                // No generic navigation/shell contract in Knot. Keep unrelated
                // legacy routing unchanged, but never approve it through here.
                break
            }
        }
        var seen = Set<String>()
        return Array(values.filter { seen.insert("\($0.kind.rawValue)|\($0.text)|\($0.target)|\($0.date?.timeIntervalSince1970 ?? 0)|\($0.action?.kind.rawValue ?? "")").inserted }.prefix(4))
    }

    static func community(_ raw: String?) -> WhisperCommunity? {
        guard let raw, !raw.isEmpty else { return nil }
        return WhisperCommunity.catalog.first { $0.id == raw || $0.name.caseInsensitiveCompare(raw) == .orderedSame }
    }

    var heading: String {
        switch kind {
        case .post: "Publish post"
        case .meeting: "Schedule meeting"
        case .reminder: "Set reminder"
        case .community: "Join \(Self.community(target)?.name ?? "community")"
        case .follow: "Follow @\(target)"
        case .tool: action?.displayLabel ?? "Review action"
        }
    }
    var icon: String {
        switch kind {
        case .post: "square.and.pencil"
        case .meeting: "calendar.badge.plus"
        case .reminder: "bell.badge"
        case .community: "person.3"
        case .follow: "person.badge.plus"
        case .tool: action?.iconName ?? "arrow.up.right"
        }
    }
    var scope: String {
        switch kind {
        case .post: target.isEmpty ? "Posts as you · visible under your profile’s current privacy" : "Posts as you · \(Self.community(target)?.name ?? target)"
        case .meeting: "Whisper meeting · no invitations sent"
        case .reminder: "One notification on this device · not Apple Reminders · removed when you switch accounts"
        case .community: "Adds this community to your interests and feed"
        case .follow: "Private profiles receive a follow request"
        case .tool: "Opens the existing screen for review. Nothing is submitted by this approval."
        }
    }
    var statusText: String {
        if let result { return result }
        switch state {
        case .pending: return "Waiting for your permission"
        case .running: return "Working…"
        case .denied: return "Denied · nothing was run"
        case .completed: return "Completed"
        case .unavailable: return "Couldn’t run this action"
        case .unconfirmed: return "Result not confirmed. Check the destination before trying again."
        case .expired: return "Approval expired. Ask Knot again to review a fresh proposal."
        }
    }
    func restored() -> Self {
        var copy = self
        if state == .pending { copy.state = .expired; copy.result = nil }
        if state == .running { copy.state = .unconfirmed; copy.result = nil }
        return copy
    }
}

struct WhisperKnotActionProposalCard: View {
    let proposal: WhisperKnotActionProposal
    let busy: Bool
    let allow: () -> Void
    let deny: () -> Void
    let cancelReminder: () -> Void
    let updateDetails: (WhisperKnotActionProposal) -> Void
    var bot: WhisperKnotBot = .main
    @State private var editing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primaryLabel: String {
        if proposal.needsDetails { return "Add details" }
        switch proposal.kind {
        case .post: return "Allow & publish"
        case .meeting: return "Allow & schedule"
        case .reminder: return "Allow & set reminder"
        case .community: return "Allow & join"
        case .follow: return "Allow & follow"
        case .tool: return "Open for review"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                WhisperKnotProfilePortrait(size: 28, expression: .calm, tint: bot.portraitTint)
                Text(bot.displayName).font(.subheadline.weight(.semibold))
                Text(proposal.state == .pending ? "Needs approval" : proposal.state == .completed ? "Action result" : "Action status")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Label(proposal.heading, systemImage: proposal.icon).font(.title3.weight(.semibold))
            Text(proposal.scope).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                if let request = proposal.originalRequest {
                    detail("Your request", request)
                }
                if !proposal.text.isEmpty {
                    detail(proposal.kind == .post ? "Post text" : "Content", proposal.text)
                }
                if !proposal.target.isEmpty {
                    detail("Destination", WhisperKnotActionProposal.community(proposal.target)?.name ?? proposal.target)
                } else if proposal.kind == .post {
                    detail("Destination", "Your Whisper profile")
                }
                if let date = proposal.date {
                    detail("When", date.formatted(date: .abbreviated, time: .shortened) + " · " + (TimeZone.current.abbreviation(for: date) ?? TimeZone.current.identifier))
                }
                if proposal.needsDetails, proposal.state == .pending {
                    Text("Add the exact details first. Nothing has been run or scheduled.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.7), in: .rect(cornerRadius: 16))
            Divider()
            if proposal.state == .pending {
                Button {
                    if proposal.needsDetails { editing = true } else { allow() }
                } label: {
                    Text(primaryLabel).font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent).tint(.blue)
                .buttonBorderShape(.capsule).controlSize(.large).disabled(busy)
                Button(action: deny) {
                    Text("Don’t allow").font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.bordered).tint(.secondary)
                .buttonBorderShape(.capsule).controlSize(.large)
                if !proposal.needsDetails, [.post, .meeting, .reminder, .follow].contains(proposal.kind) {
                    Button("Edit details") { editing = true }
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).disabled(busy)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    if proposal.state == .running { ProgressView().controlSize(.small) }
                    else { Image(systemName: proposal.state == .completed ? "checkmark.circle.fill" : "info.circle") }
                    Text(proposal.statusText).font(.subheadline).textSelection(.enabled)
                }
                .foregroundStyle(proposal.state == .completed ? Color.green : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if proposal.reminderID != nil, proposal.state == .completed {
                Button("Cancel reminder", role: .destructive, action: cancelReminder).font(.subheadline).frame(minHeight: 44)
            }
            if let id = proposal.postID { WhisperKnotSharedPostMessage(postID: id) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.primary.opacity(0.08)) }
        .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: proposal.state)
        .sheet(isPresented: $editing) {
            WhisperKnotProposalDetailsEditor(proposal: proposal) { revised in
                updateDetails(revised)
                editing = false
            }
        }
        .onChange(of: proposal.state) { _, state in if state != .pending { editing = false } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in editing = false }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WhisperKnotProposalDetailsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var proposal: WhisperKnotActionProposal
    @State private var selectedDate = Date().addingTimeInterval(3600)
    let save: (WhisperKnotActionProposal) -> Void

    private var requiresDate: Bool { proposal.kind == .meeting || proposal.kind == .reminder }
    var body: some View {
        NavigationStack {
            Form {
                if let request = proposal.originalRequest { Section("Your request") { Text(request) } }
                Section("Exact details") {
                    if proposal.kind == .follow {
                        TextField("Username", text: $proposal.target).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        TextField(proposal.kind == .post ? "Post text" : "Title or reminder", text: $proposal.text, axis: .vertical).lineLimit(3...10)
                    }
                    if requiresDate {
                        DatePicker("Date & time", selection: $selectedDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Saving details does not allow this action. Review the updated card, then explicitly allow it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Review details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if requiresDate { proposal.date = selectedDate }
                        if proposal.kind == .follow { proposal.target = WhisperEmberAction.cleanUsername(proposal.target) }
                        save(proposal)
                    }
                    .disabled((proposal.kind == .follow ? proposal.target : proposal.text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (requiresDate && selectedDate <= Date()))
                }
            }
            .onAppear { if let date = proposal.date { selectedDate = date } }
        }
    }
}

/// One write at a time across Knot chat presentations. No automatic retries.
@MainActor @Observable
final class WhisperKnotActionExecutor {
    static let shared = WhisperKnotActionExecutor()
    private(set) var busy = false
    private(set) var activity: String?

    func execute(_ proposal: WhisperKnotActionProposal, isCurrent: @MainActor () -> Bool) async -> WhisperKnotActionProposal {
        var output = proposal
        guard !busy, proposal.state == .pending, isCurrent(), AccountStorage.currentUserID != "guest" else {
            output.state = .unavailable; output.result = "This approval is no longer available. Ask Knot again."
            return output
        }
        busy = true
        activity = proposal.heading + "…"
        defer { busy = false; activity = nil }
        let generation = AccountStorage.generation
        func valid() -> Bool { generation == AccountStorage.generation && !Task.isCancelled && isCurrent() }
        func finish(_ state: WhisperKnotActionProposal.State, _ text: String) -> WhisperKnotActionProposal {
            output.state = state; output.result = text; return output
        }
        switch proposal.kind {
        case .post:
            let caption = proposal.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = WhisperUserService.shared.me?.username ?? ""
            guard !caption.isEmpty, caption.count <= WhisperVerifiedPerks.characterLimit(username: username),
                  !caption.contains("::"), !WhisperDearEmberService.matches(caption) else {
                return finish(.unavailable, "This draft needs the post composer. Ask Knot for a shorter plain-text post.")
            }
            let community = WhisperKnotActionProposal.community(proposal.target)
            guard proposal.target.isEmpty || community != nil else { return finish(.unavailable, "That community isn’t in the Whisper catalog. Nothing was posted.") }
            if let community, community.requiresJasperLink, JasperConnectClient.shared.connection == nil {
                return finish(.unavailable, "Link Jasper before posting in this community. Nothing was posted.")
            }
            guard valid() else { return finish(.expired, "Approval expired.") }
            let row = await WhisperBackendService.shared.createPost(kind: "text", caption: caption, symbol: "quote.opening", accentHex: nil, mediaCount: 0, isGhost: false,
                communityID: community?.id, communityName: community?.name, postID: proposal.id.uuidString.lowercased())
            guard valid() else { return finish(.unconfirmed, "Check your profile to confirm publication.") }
            guard let row else { return finish(.unconfirmed, "Couldn’t confirm publication. Check your profile before posting again.") }
            output.postID = row.id
            if let community, row.community_id != community.id {
                return finish(.completed, "Published on your profile, but community placement wasn’t confirmed.")
            }
            return finish(.completed, "Published as you" + (community.map { " in \($0.name)." } ?? "."))
        case .meeting:
            guard let date = proposal.date, date > Date(), !proposal.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, proposal.text.count <= 200 else {
                return finish(.unavailable, "Ask Knot for a meeting title and a future date and time. Nothing was scheduled.")
            }
            do {
                let row = try await WhisperMeetingService.shared.create(title: proposal.text, scheduledAt: date, id: proposal.id.uuidString.lowercased())
                guard valid() else { return finish(.unconfirmed, "Check Meet to confirm the meeting.") }
                return finish(.completed, "Meeting created. No invitations sent.\n" + WhisperMeetingService.link(for: row.id))
            } catch { return finish(.unconfirmed, "Couldn’t confirm the meeting. Check Meet before scheduling again.") }
        case .community:
            guard let community = WhisperKnotActionProposal.community(proposal.target) else { return finish(.unavailable, "That community is unavailable.") }
            guard !community.requiresJasperLink || JasperConnectClient.shared.connection != nil else { return finish(.unavailable, "Link Jasper before joining this community.") }
            await WhisperUserService.shared.refreshMe()
            guard valid(), WhisperUserService.shared.lastError == nil, let me = WhisperUserService.shared.me, me.user_id.lowercased() == AccountStorage.currentUserID.lowercased() else { return finish(.unavailable, "Couldn’t verify your profile. Nothing was changed.") }
            var interests = me.interests ?? []
            if interests.contains(where: { $0.caseInsensitiveCompare(community.name) == .orderedSame }) { return finish(.completed, "You’re already in \(community.name).") }
            interests.append(community.name)
            let ok = await WhisperUserService.shared.updateInterests(interests)
            guard valid() else { return finish(.unconfirmed, "Check your communities to confirm membership.") }
            return finish(ok ? .completed : .unconfirmed, ok ? "Joined \(community.name)." : "Couldn’t confirm membership. Check your communities before trying again.")
        case .follow:
            guard !proposal.target.isEmpty else { return finish(.unavailable, "Ask Knot for an exact username first.") }
            guard let user = await WhisperEmberActionRouter.shared.resolveUser(proposal.target), valid() else { return finish(.unavailable, "Couldn’t verify that profile. Nothing was sent.") }
            let outcome = await WhisperFollowService.shared.attemptFollow(userID: user.user_id, username: user.username)
            guard valid() else { return finish(.unconfirmed, "Check the profile to confirm your follow status.") }
            switch outcome {
            case .followed: return finish(.completed, "Following @\(user.username).")
            case .requested: return finish(.completed, "Follow request sent to @\(user.username).")
            case .alreadyFollowing: return finish(.completed, "You already follow @\(user.username).")
            default: return finish(.unconfirmed, "Couldn’t confirm the follow. Check the profile before trying again.")
            }
        case .reminder:
            guard let date = proposal.date, date > Date(), !proposal.text.isEmpty, proposal.text.count <= 200 else { return finish(.unavailable, "Ask Knot for a short reminder and a future date and time.") }
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard valid() else { return finish(.expired, "Approval expired. Nothing was scheduled.") }
                guard granted else { return finish(.unavailable, "Notifications are disabled. Enable them in iPhone Settings, then ask Knot again.") }
                guard date > Date() else { return finish(.unavailable, "That reminder time has passed. Ask Knot for a new time.") }
                let pending = await center.pendingNotificationRequests()
                guard valid() else { return finish(.expired, "Approval expired. Nothing was scheduled.") }
                guard pending.count < 60 else { return finish(.unavailable, "This device has too many scheduled notifications. Cancel an existing reminder first.") }
                let identifier = "knot-reminder:\(AccountStorage.currentUserID.lowercased()):\(proposal.id)"
                let content = UNMutableNotificationContent()
                content.title = "Whisper reminder"
                content.body = proposal.text
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
                // Record exact identifiers before suspension so account changes
                // can synchronously cancel them, including after a process restart.
                let identifiers = pending.map(\.identifier).filter { $0.hasPrefix("knot-reminder:\(AccountStorage.currentUserID.lowercased()):") }
                AccountStorage.set(identifiers + [identifier], forKey: "knotReminderIdentifiers")
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                guard valid() else {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                    return finish(.expired, "Reminder cancelled because the conversation or account changed.")
                }
                output.reminderID = identifier
                return finish(.completed, "Reminder scheduled on this device. Delivery follows your iPhone’s notification and Focus settings.")
            } catch { return finish(.unavailable, "Couldn’t schedule this reminder. Ask Knot again when notifications are available.") }
        case .tool:
            guard let action = proposal.action, valid() else { return finish(.expired, "Approval expired.") }
            guard action.kind == .schedule, !proposal.needsDetails, let date = proposal.date, date > Date(), proposal.text.count <= 200 else {
                return finish(.unavailable, "This review needs an exact meeting title, future time and invitee. Nothing was created or sent.")
            }
            // The caller requests navigation afterward; this is not proof that
            // a screen appeared or that a meeting/invitation was submitted.
            return finish(.completed, "Meeting review requested—not submitted. No meeting or invitation has been created.")
        }
    }
}
