import SwiftUI

/// Model-authored details are a draft, never a grant. Identity and state are native.
nonisolated struct WhisperKnotResponsibilitySpec: Codable, Hashable, Sendable {
    let kind: String
    let title: String
    let instruction: String
    let searchQuery: String
    let minIntervalMinutes: Int
    let maxIntervalMinutes: Int
    let timezone: String
    let quietStart: Int
    let quietEnd: Int
    let endsAtISO: String

    var endDate: Date? { WhisperEmberActionParser.parseWhen(endsAtISO) }
    var valid: Bool {
        guard ["public_tracking", "goal_followup", "creator_performance"].contains(kind),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf16.count <= 120,
              !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, instruction.utf16.count <= 3000,
              searchQuery.utf16.count <= 1000,
              (kind == "public_tracking" ? !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : searchQuery.isEmpty),
              [60, 180, 360, 1440].contains(minIntervalMinutes),
              maxIntervalMinutes >= minIntervalMinutes, maxIntervalMinutes <= 10080,
              (0...23).contains(quietStart), (0...23).contains(quietEnd),
              timezone.count <= 80, TimeZone(identifier: timezone) != nil,
              let endDate, endDate > Date().addingTimeInterval(60), endDate <= Date().addingTimeInterval(30 * 86400) else { return false }
        return true
    }
    var cadence: String {
        func interval(_ minutes: Int) -> String {
            if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
            if minutes % 60 == 0 { return "\(minutes / 60)h" }
            return "\(minutes)m"
        }
        return minIntervalMinutes == maxIntervalMinutes ? "Every \(interval(minIntervalMinutes))" : "Every \(interval(minIntervalMinutes))–\(interval(maxIntervalMinutes))"
    }
    var quietHours: String { quietStart == quietEnd ? "None" : String(format: "%02d:00–%02d:00", quietStart, quietEnd) }
    func approval(id: UUID, bot: WhisperKnotBot, conversationID: UUID, epoch: String) -> WhisperKnotResponsibilityApproval? {
        guard valid, let endDate else { return nil }
        return .init(approvalEpoch: epoch, id: id.uuidString.lowercased(), bot: bot.rawValue,
            conversationID: conversationID.uuidString.lowercased(), kind: kind, title: title, instruction: instruction,
            searchQuery: searchQuery, minIntervalMinutes: minIntervalMinutes, maxIntervalMinutes: maxIntervalMinutes,
            timezone: timezone, quietStart: quietStart, quietEnd: quietEnd, endsAt: endDate.timeIntervalSince1970 * 1000,
            creatorReadConsent: kind == "creator_performance" ? "knot_creator_performance_v1" : nil)
    }
}

nonisolated struct WhisperKnotResponsibilityProposal: Codable, Hashable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case pending, approved, declined, expired, unconfirmed }
    var id = UUID()
    let spec: WhisperKnotResponsibilitySpec
    let botID: String
    let conversationID: UUID
    var createdAt = Date()
    var state: State = .pending
    var reviewable: Bool { state == .pending && spec.valid && Date().timeIntervalSince(createdAt) < 900 }
    var status: String {
        switch state {
        case .pending: "Not approved"
        case .approved: "Responsibility saved"
        case .declined: "Not assigned"
        case .expired: "Review expired · ask Knot again"
        case .unconfirmed: "Check Responsibilities before trying again"
        }
    }
    func restored() -> Self {
        var copy = self
        if state == .pending { copy.state = .expired }
        return copy
    }
}

struct WhisperKnotResponsibilityProposalCard: View {
    let proposal: WhisperKnotResponsibilityProposal
    let bot: WhisperKnotBot
    let review: () -> Void
    let decline: () -> Void
    let change: () -> Void
    @State private var service = WhisperKnotBackgroundService.shared
    @State private var showScheduledTask = false
    private var savedRule: WhisperKnotResponsibility? {
        service.rules.first { $0.id.lowercased() == proposal.id.uuidString.lowercased() && $0.bot == bot.rawValue && $0.conversationID.lowercased() == proposal.conversationID.uuidString.lowercased() }
    }

    var body: some View {
        Group {
            if let rule = savedRule { scheduledBubble(rule) }
            else { draftCard }
        }
        .sheet(isPresented: $showScheduledTask) {
            NavigationStack {
                WhisperKnotResponsibilitiesView(bot: bot, conversationID: proposal.conversationID, initialRuleID: proposal.id.uuidString.lowercased())
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showScheduledTask = false } } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in showScheduledTask = false }
    }

    private func scheduledBubble(_ rule: WhisperKnotResponsibility) -> some View {
        let active = rule.state == "active" && rule.endDate > Date()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 28)).foregroundStyle(.secondary).frame(width: 38, height: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(rule.title).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Text(active ? "Scheduled task · \(rule.nextDate.formatted(date: .abbreviated, time: .shortened))" : "Saved task · \(rule.state == "paused" ? "Paused" : "Ended")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button { showScheduledTask = true } label: {
                Text("View scheduled task").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                    .background(.background.opacity(0.65), in: Capsule())
            }.buttonStyle(.plain)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 26))
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Responsibility", systemImage: "checklist").font(.subheadline.weight(.medium))
                Spacer()
                if proposal.state == .approved { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Text(proposal.spec.title).font(.title3.weight(.semibold))
            Text(proposal.spec.instruction).font(.body).fixedSize(horizontal: false, vertical: true)
            if !proposal.spec.searchQuery.isEmpty {
                Label(proposal.spec.searchQuery, systemImage: "magnifyingglass").font(.subheadline).textSelection(.enabled)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.spec.cadence)
                Spacer()
                if let end = proposal.spec.endDate { Text("Until \(end.formatted(date: .abbreviated, time: .omitted))") }
            }.font(.subheadline).foregroundStyle(.secondary)
            if proposal.state == .pending {
                Button("Review & approve", action: review)
                    .buttonStyle(.borderedProminent).tint(.blue).buttonBorderShape(.capsule)
                    .controlSize(.large).disabled(!proposal.reviewable)
                HStack {
                    Button("Change in chat", action: change)
                    Spacer()
                    Button("Not now", action: decline).tint(.secondary)
                }.font(.subheadline).frame(minHeight: 44)
                if !proposal.reviewable { Text("Review expired · ask Knot again").font(.caption).foregroundStyle(.secondary) }
            } else { Text(proposal.status).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.06)) }
        .accessibilityElement(children: .contain)
    }
}

/// Review is compact but exact. No recurring request is sent before the button.
struct WhisperKnotConversationalResponsibilityReview: View {
    let proposal: WhisperKnotResponsibilityProposal
    let bot: WhisperKnotBot
    let isCurrent: @MainActor () -> Bool
    let finish: (WhisperKnotResponsibilityProposal.State) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var service = WhisperKnotBackgroundService.shared
    @State private var approval: WhisperKnotResponsibilityApproval?
    @State private var attempted = false
    @State private var saved = false
    @State private var saving = false
    @State private var operation: Task<Void, Never>?
    @State private var visible = false
    @State private var generation = AccountStorage.generation
    @State private var consentRevision = WhisperKnotContextPermission.revision

    private var validLease: Bool {
        visible && isCurrent() && generation == AccountStorage.generation && WhisperKnotContextPermission.allowed &&
        consentRevision == WhisperKnotContextPermission.revision
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(proposal.spec.title).font(.title2.weight(.semibold))
                    Text(proposal.spec.instruction).textSelection(.enabled)
                    if !proposal.spec.searchQuery.isEmpty { LabeledContent("Search only", value: proposal.spec.searchQuery) }
                }
                Section {
                    LabeledContent("Checks", value: proposal.spec.cadence)
                    LabeledContent("Quiet hours", value: proposal.spec.quietHours)
                    LabeledContent("Time zone", value: proposal.spec.timezone)
                    if let end = proposal.spec.endDate { LabeledContent("Ends", value: end.formatted(date: .abbreviated, time: .shortened)) }
                    Text("First check in about a minute, or after quiet hours. Quiet hours may defer later checks.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Permission") {
                    Text("Future checks and private updates in this \(bot.displayName) conversation. No calls, posts or actions for you. Pause or delete anytime in Responsibilities.")
                    if proposal.spec.kind == "creator_performance" {
                        WhisperKnotCreatorReadDisclosure()
                    } else {
                        Text(proposal.spec.kind == "goal_followup" ? "Checks in about your goal; it cannot see your progress, calendar or other chats." : "Searches only the public query above; unchanged findings stay quiet.")
                    }
                    Text("Whisper’s server sends this rule and prior findings through Rork AI Cloud (via Vercel AI Gateway) to OpenAI GPT‑4o for processing. Whisper stores the rule and updates privately. No other chats, profile, files or call transcripts are included.")
                    DisclosureGroup("Storage & privacy") {
                        Text("Updates and check records expire after 30 days; up to 400 recent updates are retained. Rule details are removed 30 days after their end. Imported device chat copies are separate. Public tracking sends the exact approved query to OpenAI web search.")
                        Link("OpenAI privacy", destination: URL(string: "https://openai.com/policies/privacy-policy/")!)
                        Link("Whisper privacy", destination: URL(string: "https://www.mydailywhisper.com/privacy")!)
                    }
                }.font(.subheadline)
                if let error = service.error { Section { Text(error).foregroundStyle(.secondary) } }
                Section {
                    Button(saving ? "Saving…" : attempted ? "Retry exact approval" : "Approve responsibility") {
                        guard validLease, proposal.reviewable, let approval, !saving, !service.busy else { return }
                        attempted = true; saving = true
                        operation = Task { @MainActor in
                            let success = await service.approve(approval)
                            saving = false
                            guard validLease else { return }
                            if success { saved = true; finish(.approved); Haptics.success(); dismiss() }
                        }
                    }.disabled(approval == nil || saving || service.busy || !proposal.reviewable)
                    if approval == nil {
                        Button("Refresh permission") { Task { await prepare() } }.disabled(saving || service.busy)
                    }
                }
            }
            .navigationTitle("Leave it with \(bot.displayName)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(attempted ? "Close" : "Cancel") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .task { visible = true; await prepare() }
            .onDisappear {
                visible = false; operation?.cancel()
                if attempted && !saved { finish(.unconfirmed) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in operation?.cancel(); dismiss() }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in operation?.cancel(); dismiss() }
        }
    }
    private func prepare() async {
        guard !attempted, validLease, proposal.reviewable else { return }
        approval = nil
        await service.refresh()
        guard validLease, !Task.isCancelled, let epoch = service.approvalEpoch, service.error == nil else { return }
        approval = proposal.spec.approval(id: proposal.id, bot: bot, conversationID: proposal.conversationID, epoch: epoch)
    }
}
