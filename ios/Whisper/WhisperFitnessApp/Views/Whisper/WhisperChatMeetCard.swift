import SwiftUI

/// Authoritative event state, not a local RSVP toggle or a room-join side effect.
struct WhisperChatMeetCard: View {
    let eventID: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var invitation: WhisperChatMeetInvitation?
    @State private var error: String?
    @State private var rolloutPending: Bool = false
    @State private var saving: Bool = false
    @State private var opening: Bool = false
    @State private var attempt: Int = 0
    @State private var responseTask: Task<Void, Never>?
    @State private var openTask: Task<Void, Never>?
    @State private var operation: UUID = UUID()
    @State private var openOperation: UUID = UUID()
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    @State private var accountInvalidated: Bool = false
    private var isCurrent: Bool { !closed && !accountInvalidated && generation == AccountStorage.generation }
    private var myResponse: String? { invitation?.invitees.first { $0.userID.lowercased() == AccountStorage.currentUserID.lowercased() }?.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("WhisperMeetApp").resizable().scaledToFit().frame(width: 38, height: 38).clipShape(.rect(cornerRadius: 10))
                Text("Whisper Meet").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            if let invitation {
                Text(invitation.title).font(.headline).lineLimit(3)
                Text(WhisperCalendarEmbed.formattedDate(invitation.startTime)).font(.subheadline)
                if invitation.cancelled { Text("Meeting cancelled").foregroundStyle(.secondary) }
                else {
                    HStack(spacing: 8) {
                        responseButton("Going", status: "going", symbol: "checkmark")
                        responseButton("Not going", status: "declined", symbol: "xmark")
                    }
                    Text(myResponse == nil ? "Awaiting your response" : "Your response: \(myResponse == "going" ? "Going" : "Not going")")
                        .font(.caption).foregroundStyle(.secondary)
                    if !invitation.deliveryComplete {
                        Text("Invitation delivery is incomplete. The organizer can recover delivery in Meet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(opening ? "Checking access…" : "Open in Meet") { openMeeting(invitation.meetingID) }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(saving || opening || !isCurrent)
                }
                WhisperParticipantStack(people: invitation.invitees.filter { $0.status == "going" }.map {
                    WhisperGroupMember(user_id: $0.userID, username: $0.username, profile_image_url: nil)
                }, label: "Going")
                DisclosureGroup("All responses") {
                    ForEach(invitation.invitees) { person in
                        HStack { Text(person.username).lineLimit(1); Spacer(); Text(person.responseLabel).foregroundStyle(.secondary) }
                            .font(.caption).padding(.vertical, 4)
                    }
                }.font(.caption)
            } else if error == nil { ProgressView("Loading meeting…").font(.caption) }
            if let error {
                if rolloutPending { Text("Meet rollout pending").font(.caption.weight(.semibold)) }
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button(rolloutPending ? "Check again later" : "Check access again") { attempt += 1 }
                    .frame(minHeight: 44).disabled(saving || opening || !isCurrent)
            }
        }
        .padding(14).frame(maxWidth: 280, alignment: .leading)
        .foregroundStyle(.primary).background(.regularMaterial, in: .rect(cornerRadius: 18))
        .onAppear { if !accountInvalidated, generation == AccountStorage.generation { closed = false } }
        .task(id: "\(eventID)-\(attempt)-\(scenePhase == .active)") { await reload() }
        .onChange(of: eventID) { _, _ in
            invalidateOperations(); invitation = nil; error = nil; attempt += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { invalidateOperations(); invitation = nil; error = nil; rolloutPending = false }
        }
        .onDisappear { closed = true; invalidateOperations(); invitation = nil }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
            accountInvalidated = true; closed = true; invalidateOperations(); invitation = nil; error = nil
        }
    }

    private func invalidateOperations() {
        operation = UUID(); openOperation = UUID()
        responseTask?.cancel(); responseTask = nil; openTask?.cancel(); openTask = nil
        saving = false; opening = false
    }

    private func reload() async {
        guard scenePhase == .active, !saving, !opening, isCurrent else { return }
        let request = UUID(); operation = request; error = nil; rolloutPending = false; invitation = nil
        let requestedEvent = eventID
        do {
            let result = try await WhisperChatMeetService.load(eventID: requestedEvent)
            guard !Task.isCancelled, isCurrent, operation == request,
                  result.eventID.lowercased() == requestedEvent.lowercased() else { return }
            invitation = result
        } catch {
            guard !Task.isCancelled, isCurrent, operation == request else { return }
            invitation = nil
            rolloutPending = (error as? WhisperChatMeetService.Failure) == .activationPending
            self.error = error.localizedDescription
        }
    }

    private func respond(_ status: String) {
        guard scenePhase == .active, !saving, !opening, isCurrent, invitation?.cancelled == false else { return }
        let request = UUID(); operation = request
        saving = true; error = nil; rolloutPending = false
        responseTask = Task {
            defer { if operation == request { saving = false; responseTask = nil } }
            do {
                let result = try await WhisperChatMeetService.respond(eventID: eventID, status: status)
                guard !Task.isCancelled, isCurrent, operation == request,
                      result.eventID.lowercased() == eventID.lowercased() else { return }
                invitation = result; Haptics.selection()
            } catch {
                guard !Task.isCancelled, isCurrent, operation == request else { return }
                invitation = nil
                rolloutPending = (error as? WhisperChatMeetService.Failure) == .activationPending
                self.error = error.localizedDescription
            }
        }
    }

    private func openMeeting(_ identity: String) {
        guard scenePhase == .active, isCurrent, !saving, !opening else { return }
        let request = UUID(); openOperation = request; operation = UUID(); opening = true
        let requestedEvent = eventID
        error = nil; rolloutPending = false
        openTask = Task {
            defer { if openOperation == request { opening = false; openTask = nil } }
            do {
                let result = try await WhisperChatMeetService.load(eventID: requestedEvent)
                guard !Task.isCancelled, isCurrent, scenePhase == .active, openOperation == request else { return }
                guard result.meetingID == identity else { throw WhisperChatMeetService.Failure.invalidResponse }
                invitation = result
                guard !result.cancelled else { return }
                let opened = await WhisperMeetHandoff.open(.init(idOrCode: result.meetingID))
                guard !Task.isCancelled, isCurrent, openOperation == request else { return }
                if !opened { error = "Couldn't open Meet. Try again." }
            } catch {
                guard !Task.isCancelled, isCurrent, openOperation == request else { return }
                invitation = nil
                rolloutPending = (error as? WhisperChatMeetService.Failure) == .activationPending
                self.error = error.localizedDescription
            }
        }
    }

    private func responseButton(_ title: String, status: String, symbol: String) -> some View {
        Button { respond(status) } label: {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                .background(myResponse == status ? Color.primary.opacity(0.15) : .clear, in: .capsule)
                .overlay { Capsule().strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
        }.buttonStyle(.plain).disabled(saving || opening || !isCurrent).accessibilityAddTraits(myResponse == status ? .isSelected : [])
    }
}
