import SwiftUI

struct WhisperKnotResponsibilitiesView: View {
    let bot: WhisperKnotBot
    let conversationID: UUID
    var onCompose: (() -> Void)? = nil
    var initialRuleID: String? = nil
    @State private var focusedRuleID: String?
    @State private var service = WhisperKnotBackgroundService.shared
    @State private var showCreate = false
    @State private var confirmErase = false
    @State private var deleting: WhisperKnotResponsibility?
    @State private var contactRule: WhisperKnotResponsibility?
    @State private var contact = WhisperKnotContactService.shared
    @Environment(\.dismiss) private var dismiss
    private var rules: [WhisperKnotResponsibility] { service.rules.filter { $0.bot == bot.rawValue } }

    var body: some View {
        List {
            Section {
                if let onCompose { Button("Assign in chat", systemImage: "bubble.left") { onCompose() } }
                else { Button("Assign a responsibility", systemImage: "plus") { showCreate = true } }
            }
            if let error = service.error {
                Section { Text(error).foregroundStyle(.secondary); Button("Refresh") { Task { await service.refresh() } } }
            }
            if rules.isEmpty {
                Section { ContentUnavailableView("Nothing assigned yet", systemImage: "checklist", description: Text("Keep up with a public topic, a goal or your Whisper performance.")) }
            } else {
                Section("This Knot’s responsibilities") {
                    ForEach(rules) { rule in
                        NavigationLink {
                            responsibilityDetail(rule)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(rule.title).font(.headline)
                                Text(rule.lastOutcome).font(.caption).foregroundStyle(.secondary)
                                if rule.state == "active" {
                                    Text("Next check \(rule.nextDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("Contact & privacy") {
                Label("Private chat updates", systemImage: "bubble.left.and.bubble.right")
                Text("Saved updates sync while Whisper is open, with an unread badge in Messages. Notifications and call invitations are optional, separately reviewed contact permissions for each responsibility. Calls only connect after you answer inside Whisper.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Rules, recent check records and updates are stored privately on Whisper’s server, not in other Knots’ memory. Updates and check records expire after 30 days; rule details are removed 30 days after their end date. Up to 400 recent background messages and 20 responsibilities are retained per account. Imported chat copies follow this device’s 40-conversation history limit; delete them from chat history when needed.")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Button("Pause all Knots’ responsibilities", role: .destructive) {
                    Task { do { try await service.revokeAll() } catch { service.error = "Couldn’t confirm the pause. Refresh and try again." } }
                }.disabled(service.busy)
                Button("Delete all background data…", role: .destructive) { confirmErase = true }.disabled(service.busy)
            }
        }
        .navigationTitle("Responsibilities").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Menu { Button("Enter details manually") { showCreate = true } } label: { Image(systemName: "ellipsis") } } }
        .task {
            await service.refresh()
            guard !Task.isCancelled else { return }
            if let initialRuleID, rules.contains(where: { $0.id == initialRuleID && $0.conversationID.lowercased() == conversationID.uuidString.lowercased() }) { focusedRuleID = initialRuleID }
            await service.syncMessages(); await contact.refresh()
        }
        .navigationDestination(isPresented: Binding(get: { focusedRuleID != nil }, set: { if !$0 { focusedRuleID = nil } })) {
            if let rule = rules.first(where: { $0.id == focusedRuleID }) { responsibilityDetail(rule) }
            else { ContentUnavailableView("Task no longer available", systemImage: "calendar") }
        }
        .refreshable { await service.refresh(); await service.syncMessages(force: true) }
        .sheet(isPresented: $showCreate) {
            NavigationStack { WhisperKnotAssignResponsibilityView(bot: bot, conversationID: conversationID) }
        }
        .sheet(item: $contactRule) { rule in NavigationStack { WhisperKnotContactReview(rule: rule) } }
        .confirmationDialog("Delete all background responsibilities and server updates?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Delete background data", role: .destructive) { Task { await service.eraseAll() } }
        } message: { Text("Stops every Knot’s checks and deletes the saved server rules, updates and contact records. A content-free timestamp for the daily invitation safety limit expires within 24 hours. Existing device-local chat copies are not removed.") }
        .confirmationDialog("Delete this responsibility?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete responsibility", role: .destructive) {
                if let rule = deleting { Task { await service.change(rule, action: "delete") } }
                deleting = nil
            }
        } message: { Text("Stops its checks and removes its server updates. Messages already imported into a local chat are kept.") }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
    }

    private func responsibilityDetail(_ selected: WhisperKnotResponsibility) -> some View {
        let rule = service.rules.first { $0.id == selected.id } ?? selected
        return Form {
            Section(rule.title) {
                Text(rule.instruction).textSelection(.enabled)
                if !rule.searchQuery.isEmpty { LabeledContent("Public search", value: rule.searchQuery) }
                LabeledContent("Status", value: rule.lastOutcome)
                if rule.state == "active" { LabeledContent("Next check", value: rule.nextDate.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Ends", value: rule.endDate.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Approved boundaries") {
                if rule.kind == "creator_performance" { WhisperKnotCreatorReadDisclosure() }
                Text("Read, check and report privately to you. No posting, messaging other people, payments, account changes or shell access. Contact needs a separate approval below.")
                LabeledContent("Minimum interval", value: "\(rule.minIntervalMinutes) minutes")
                LabeledContent("Latest next check", value: "\(rule.maxIntervalMinutes) minutes later")
                LabeledContent("Time zone", value: rule.timezone)
                LabeledContent("Quiet hours", value: rule.quietStart == rule.quietEnd ? "None" : String(format: "%02d:00–%02d:00", rule.quietStart, rule.quietEnd))
                Text("Knot can choose its next check only within these intervals and before the end date. Quiet hours defer work as well as updates. Travel doesn’t silently change the approved time zone.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Contact") {
                LabeledContent("Update notifications", value: rule.contact?.push == true ? "Approved" : "Off")
                LabeledContent("Call invitations", value: rule.contact?.calls == true ? "Approved" : "Off")
                if rule.state == "active" { Button("Review contact permission") { contactRule = rule } }
            }
            if !contact.invitations.filter({ $0.ruleID == rule.id }).isEmpty {
                Section("Call invitations") {
                    ForEach(contact.invitations.filter { $0.ruleID == rule.id }) { invitation in
                        HStack {
                            Label(invitation.status, systemImage: invitation.state == "missed" ? "phone.arrow.down.left.fill" : "phone")
                            Spacer()
                            Text(Date(timeIntervalSince1970: invitation.createdAt / 1000), format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error = service.error { Section { Text(error).foregroundStyle(.secondary) } }
            Section {
                if service.rules.contains(where: { $0.id == selected.id }) {
                    if rule.state == "active" {
                        Button("Pause checks") { Task { await service.change(rule, action: "pause") } }
                    } else if rule.endDate > Date() {
                        Button("Resume approved checks") { Task { await service.change(rule, action: "resume") } }
                    }
                    Button("Delete responsibility…", role: .destructive) { deleting = rule }
                } else { Text("This responsibility was deleted.").foregroundStyle(.secondary) }
            }.disabled(service.busy)
        }.navigationTitle("Responsibility").navigationBarTitleDisplayMode(.inline)
    }
}

struct WhisperKnotAssignResponsibilityView: View {
    let bot: WhisperKnotBot
    let conversationID: UUID
    private let sourceTruncated: Bool

    init(bot: WhisperKnotBot, conversationID: UUID, sourceText: String? = nil) {
        self.bot = bot; self.conversationID = conversationID
        let source = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sourceTruncated = source.count > 3000
        _instruction = State(initialValue: String(source.prefix(3000)))
        _title = State(initialValue: String(source.replacingOccurrences(of: "\n", with: " ").prefix(80)))
        _kind = State(initialValue: source.isEmpty ? "public_tracking" : "goal_followup")
    }
    @Environment(\.dismiss) private var dismiss
    @State private var service = WhisperKnotBackgroundService.shared
    @State private var ruleID = UUID()
    @State private var kind = "public_tracking"
    @State private var title = ""
    @State private var instruction = ""
    @State private var searchQuery = ""
    @State private var interval = 360
    @State private var adaptive = true
    @State private var quietStart = 22
    @State private var quietEnd = 8
    @State private var endsAt = Date().addingTimeInterval(7 * 86400)
    @State private var approval: WhisperKnotResponsibilityApproval?
    @State private var showReview = false
    @State private var accepted = false
    @State private var approvalAttempted = false
    private let timezone = TimeZone.current.identifier
    private var canReview: Bool {
        service.approvalEpoch != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 120 &&
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && instruction.count <= 3000 &&
        (kind != "public_tracking" || (!searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchQuery.count <= 1000))
    }
    var body: some View {
        Form {
            Section("Assign to \(bot.displayName)") {
                if sourceTruncated { Text("This draft uses the first 3,000 characters of your message. Review and shorten it to the exact responsibility you want.").font(.caption).foregroundStyle(.secondary) }
                Picker("Responsibility", selection: $kind) {
                    Text("Public topic tracking").tag("public_tracking")
                    Text("Goal check-in").tag("goal_followup")
                    Text("My Whisper performance").tag("creator_performance")
                }
                TextField("Name this responsibility", text: $title).onChange(of: title) { _, value in title = String(value.prefix(120)) }
                TextField("What should Knot check or help you follow through on?", text: $instruction, axis: .vertical)
                    .lineLimit(3...8).onChange(of: instruction) { _, value in instruction = String(value.prefix(3000)) }
                if kind == "public_tracking" {
                    TextField("Exact public search query", text: $searchQuery, axis: .vertical)
                        .onChange(of: searchQuery) { _, value in searchQuery = String(value.prefix(1000)) }
                    Text("Only this query goes to public web search. Keep private details out. Knot reports meaningful new findings, not unchanged results.").font(.caption).foregroundStyle(.secondary)
                } else if kind == "creator_performance" {
                    WhisperKnotCreatorReadDisclosure()
                } else {
                    Text("A scheduled check-in about the goal you supply—not monitoring your progress, calendar or other messages.").font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(approvalAttempted)
            Section("Schedule & limits") {
                Picker("Check no more often than", selection: $interval) {
                    Text("Hourly").tag(60); Text("Every 3 hours").tag(180); Text("Every 6 hours").tag(360); Text("Daily").tag(1440)
                }
                Toggle("Let Knot choose later checks", isOn: $adaptive)
                Text(adaptive ? "Knot may wait longer when useful, up to seven days between checks, within your end date." : "Uses your chosen interval; quiet hours may defer a check.").font(.caption).foregroundStyle(.secondary)
                DatePicker("Stop after", selection: $endsAt, in: Date().addingTimeInterval(3600)...Date().addingTimeInterval(30 * 86400))
                Picker("Quiet hours start", selection: $quietStart) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker("Quiet hours end", selection: $quietEnd) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Text("Time zone: \(timezone). Matching start and end disables quiet hours. The first check is scheduled about a minute after approval, or after quiet hours.").font(.caption).foregroundStyle(.secondary)
            }.disabled(approvalAttempted)
            if service.approvalEpoch == nil {
                Section {
                    Text("Refresh your permissions before reviewing a new responsibility.").font(.caption).foregroundStyle(.secondary)
                    Button("Refresh permissions") { Task { await service.refresh() } }.disabled(service.busy)
                }
            }
            Section {
                Button("Review exact rule") {
                    guard let epoch = service.approvalEpoch else { return }
                    approvalAttempted = false
                    approval = WhisperKnotResponsibilityApproval(approvalEpoch: epoch, id: ruleID.uuidString.lowercased(), bot: bot.rawValue, conversationID: conversationID.uuidString.lowercased(), kind: kind,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines), instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines), searchQuery: kind == "public_tracking" ? searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                        minIntervalMinutes: interval, maxIntervalMinutes: adaptive ? 10080 : interval, timezone: timezone, quietStart: quietStart, quietEnd: quietEnd, endsAt: endsAt.timeIntervalSince1970 * 1000,
                        creatorReadConsent: kind == "creator_performance" ? "knot_creator_performance_v1" : nil)
                    showReview = true
                }.disabled(!canReview || service.busy || approvalAttempted)
            }
        }
        .navigationTitle("Assign responsibility").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(service.busy) } }
        .sheet(isPresented: $showReview, onDismiss: { if accepted || approvalAttempted { dismiss() } }) {
            if let approval {
                NavigationStack {
                    Form {
                        Section("Approve this rule for \(bot.displayName)") {
                            Text(approval.title).font(.headline)
                            Text(approval.instruction)
                            if !approval.searchQuery.isEmpty { LabeledContent("Search only", value: approval.searchQuery) }
                            LabeledContent("Interval", value: "\(approval.minIntervalMinutes)–\(approval.maxIntervalMinutes) minutes")
                            LabeledContent("Ends", value: Date(timeIntervalSince1970: approval.endsAt / 1000).formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Time zone", value: approval.timezone)
                            LabeledContent("Quiet hours", value: approval.quietStart == approval.quietEnd ? "None" : String(format: "%02d:00–%02d:00", approval.quietStart, approval.quietEnd))
                        }
                        Section("Your permission") {
                            if approval.kind == "creator_performance" { WhisperKnotCreatorReadDisclosure() }
                            Text("Approve future read/check/report runs and private assistant messages in this conversation within this exact rule. No other actions or calls are authorized. Pause or delete it in Responsibilities at any time.")
                            Text("Whisper stores the rule, check records and delivered updates privately on its server. The assigned instructions, previous finding and permitted evidence go through Whisper’s server and Rork AI Cloud (via Vercel AI Gateway) to OpenAI GPT-4o for processing. Public tracking sends only your exact public query to OpenAI web search. Other chats, profile, attachments and call transcripts are not included. Recent server updates and check records expire after 30 days. Up to 400 recent updates are retained; imported device chat copies are separate.")
                                .font(.caption).foregroundStyle(.secondary)
                            Link("OpenAI privacy", destination: URL(string: "https://openai.com/policies/privacy-policy/")!)
                            Link("Whisper privacy", destination: URL(string: "https://www.mydailywhisper.com/privacy")!)
                        }
                        if let error = service.error { Section { Text(error).foregroundStyle(.secondary) } }
                        Section {
                            Button(service.busy ? "Saving…" : "Approve this responsibility") {
                                approvalAttempted = true
                                Task { if await service.approve(approval) { accepted = true; showReview = false } }
                            }.disabled(service.busy)
                        }
                    }
                    .navigationTitle("Review permission").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(approvalAttempted ? "Close & review list" : "Back") { showReview = false }.disabled(service.busy) } }
                    .interactiveDismissDisabled(service.busy)
                }
            }
        }
        .interactiveDismissDisabled(service.busy)
        .task { await service.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
    }
}
