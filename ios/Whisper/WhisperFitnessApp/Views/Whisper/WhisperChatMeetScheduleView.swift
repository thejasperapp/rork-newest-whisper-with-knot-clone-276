import SwiftUI

struct WhisperChatMeetScheduleView: View {
    let conversationKind: String
    var peerID: String? = nil
    var groupID: UUID? = nil
    let conversationTitle: String
    let inviteeNames: [String]
    var onScheduled: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var title: String = ""
    @State private var date: Date = Date().addingTimeInterval(3600)
    @State private var minutes: Int = 30
    @State private var request: WhisperChatMeetService.ScheduleRequest?
    @State private var task: Task<Void, Never>?
    @State private var openTask: Task<Void, Never>?
    @State private var opening: Bool = false
    @State private var showsPermissions: Bool = false
    @State private var operation: UUID = UUID()
    @State private var openOperation: UUID = UUID()
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var confirmed: WhisperChatMeetInvitation?
    @State private var savedEventID: String?
    @State private var savedMeetingID: String?
    @State private var rolloutPending: Bool = false
    @State private var closed: Bool = false
    @State private var showsLeave: Bool = false
    @State private var generation: UUID = AccountStorage.generation

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("WhisperMeetApp").resizable().scaledToFit().frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Meet with \(conversationTitle)").font(.headline)
                            Text("Invite this chat after Meet verifies permission. Each person chooses Going or Not going.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                if WhisperChatMeetService.holdsNewInvitations {
                    Section("Rollout paused") {
                        Text("Scheduling is not enabled in this version. No invitation is created from this form while the rollout is paused.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if conversationKind == "direct", peerID != nil {
                    Section {
                        Button("Review Meet invitation permissions") { showsPermissions = true }
                            .frame(minHeight: 44).disabled(isSaving || opening)
                    }
                }
                Section("Meeting") {
                    TextField("Meeting title", text: $title).onChange(of: title) { _, value in if value.count > 120 { title = String(value.prefix(120)) } }
                    DatePicker("Starts", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Picker("Duration", selection: $minutes) {
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                }.disabled(isSaving || request != nil)
                Section(confirmed == nil ? "Chat preview · not an invitation roster" : "Confirmed invitees") {
                    if let confirmed {
                        ForEach(confirmed.invitees) { person in
                            LabeledContent(person.username, value: person.responseLabel)
                        }
                    } else {
                        Text("You (organizer)")
                        ForEach(Array(inviteeNames.enumerated()), id: \.offset) { _, name in Text(name) }
                    }
                    Text(eligibilityExplanation)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let confirmed {
                    Section {
                        Text(confirmed.cancelled ? "This meeting was cancelled. Close this request before scheduling another." : confirmed.deliveryComplete ? "Meeting scheduled" : "Meeting saved; chat delivery is still pending.")
                        if !confirmed.cancelled {
                            Button(opening ? "Checking access…" : "Open in Meet") { openMeeting() }
                                .disabled(opening || isSaving)
                        }
                    }
                }
                if let error {
                    Section(rolloutPending ? "Meet rollout pending" : "Not confirmed") {
                        Text(error).foregroundStyle(rolloutPending ? Color.secondary : Color.red)
                    }
                }
                Section {
                    Button { schedule() } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView() }
                            Text(isSaving ? "Confirming meeting…" : WhisperChatMeetService.holdsNewInvitations && savedEventID == nil ? "Scheduling paused" : rolloutPending ? "Check again later" : savedEventID != nil ? "Retry invitation delivery" : request == nil ? "Schedule invitation" : "Retry same meeting")
                                .fontWeight(.semibold)
                            Spacer()
                        }.frame(minHeight: 44)
                    }.disabled((WhisperChatMeetService.holdsNewInvitations && savedEventID == nil) || isSaving || opening || confirmed?.cancelled == true || (request == nil && (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || date <= Date())))
                    if request != nil { Text("This open form keeps the same request and frozen details for retries. Meet delivers invitation cards; Whisper won't send extra copies.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Schedule a Meet").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsPermissions) {
                if let peerID { WhisperChatMeetPermissionsView(peerID: peerID, peerName: conversationTitle) }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(confirmed?.cancelled == true ? "Done" : "Cancel") { if request != nil && confirmed?.cancelled != true { showsLeave = true } else { close() } }.disabled(isSaving) } }
            .confirmationDialog("Leave this meeting request?", isPresented: $showsLeave, titleVisibility: .visible) {
                Button("Leave request", role: .destructive) { close() }
                Button("Keep checking", role: .cancel) {}
            } message: { Text("The meeting may already have been saved. Check Meet before creating another one. Leaving does not cancel it.") }
        }
        .interactiveDismissDisabled(isSaving || request != nil || !title.isEmpty)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                operation = UUID(); openOperation = UUID()
                task?.cancel(); task = nil; isSaving = false
                openTask?.cancel(); openTask = nil; opening = false
                confirmed = nil
            }
        }
        .onDisappear { closed = true; task?.cancel(); openTask?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in close() }
    }
    private var eligibilityExplanation: String {
        switch conversationKind {
        case "direct":
            "The recipient must approve your one-way Meet invitation permission on the server. Existing messages or on-device chat approvals do not grant it. An invitation never joins a call."
        case "dating":
            "Meet checks that both eligible, adult-attested, unblocked people currently chose Again for their same latest recorded date. Call attendance or completion is not required. Each invitation stays tied to that original date; changing or removing its qualifying decisions permanently revokes it, even if changed back. RSVP and Join remain separate."
        case "group":
            "Any current member or the owner can schedule. Meet freezes the whole server roster: 2–20 distinct eligible accounts including the owner, with no blocked pair and no selected subset. Direct permission is not needed. New members cannot access old invitations. Removing any frozen person or deleting the group permanently revokes that entire invitation for everyone; re-adding them cannot restore it. Hiding a chat on this device does not remove membership. RSVP and Join remain separate."
        default: "Meet must verify current conversation eligibility. An invitation never joins a call."
        }
    }

    private func close() { closed = true; task?.cancel(); openTask?.cancel(); dismiss() }
    private func openMeeting() {
        guard scenePhase == .active, !closed, !opening, !isSaving, let savedEventID, let savedMeetingID,
              generation == AccountStorage.generation else { return }
        let token = UUID(); openOperation = token
        opening = true; error = nil; rolloutPending = false
        openTask = Task {
            defer { if openOperation == token { opening = false; openTask = nil } }
            do {
                // Reauthorize immediately before handing off; opening is never an RSVP or Join.
                let result = try await WhisperChatMeetService.load(eventID: savedEventID)
                guard !Task.isCancelled, !closed, scenePhase == .active, openOperation == token, generation == AccountStorage.generation else { return }
                guard result.meetingID == savedMeetingID else { throw WhisperChatMeetService.Failure.invalidResponse }
                confirmed = result
                guard !result.cancelled else { return }
                let opened = await WhisperMeetHandoff.open(.init(idOrCode: result.meetingID))
                guard !Task.isCancelled, !closed, openOperation == token, generation == AccountStorage.generation else { return }
                if !opened { error = "Couldn't open Meet. Try again." }
            } catch {
                guard !Task.isCancelled, !closed, scenePhase == .active, openOperation == token, generation == AccountStorage.generation else { return }
                confirmed = nil
                rolloutPending = (error as? WhisperChatMeetService.Failure) == .activationPending
                self.error = error.localizedDescription
            }
        }
    }
    private func schedule() {
        guard scenePhase == .active, !isSaving, !opening, !closed, confirmed?.cancelled != true, generation == AccountStorage.generation else { return }
        guard !WhisperChatMeetService.holdsNewInvitations || savedEventID != nil else { return }
        if request == nil {
            guard date > Date(), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let formatter = ISO8601DateFormatter()
            request = .init(operation_id: UUID().uuidString.lowercased(), conversation_kind: conversationKind,
                peer_id: peerID, group_id: groupID?.uuidString.lowercased(), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                starts_at: formatter.string(from: date), ends_at: formatter.string(from: date.addingTimeInterval(Double(minutes * 60))), timezone: TimeZone.current.identifier)
        }
        guard let request else { return }
        let token = UUID(); operation = token
        isSaving = true; error = nil; rolloutPending = false
        task = Task {
            defer { if operation == token { isSaving = false; task = nil } }
            do {
                let result: WhisperChatMeetInvitation
                if let savedEventID {
                    result = try await WhisperChatMeetService.retry(eventID: savedEventID)
                } else {
                    result = try await WhisperChatMeetService.schedule(request)
                }
                guard !Task.isCancelled, !closed, scenePhase == .active, operation == token, generation == AccountStorage.generation else { return }
                if let savedMeetingID, result.meetingID != savedMeetingID { throw WhisperChatMeetService.Failure.invalidResponse }
                savedEventID = result.eventID; savedMeetingID = result.meetingID
                confirmed = result
                if result.deliveryComplete && !result.cancelled { Haptics.success(); onScheduled(); close() }
            } catch {
                guard !Task.isCancelled, !closed, scenePhase == .active, operation == token, generation == AccountStorage.generation else { return }
                confirmed = nil
                rolloutPending = (error as? WhisperChatMeetService.Failure) == .activationPending
                self.error = error.localizedDescription
            }
        }
    }
}
