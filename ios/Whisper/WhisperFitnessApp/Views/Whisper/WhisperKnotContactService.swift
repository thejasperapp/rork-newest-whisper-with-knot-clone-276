import SwiftUI
import UserNotifications

nonisolated struct WhisperKnotContactGrant: Codable, Sendable {
    let push: Bool
    let calls: Bool
}
nonisolated struct WhisperKnotContactApproval: Encodable, Sendable {
    let consentVersion = "knot_contact_v1"
    let approvalID: String
    let approvalEpoch: String
    let ruleRevision: String
    let push: Bool
    let calls: Bool
    let maxCallsPerDay = 1
}
nonisolated struct WhisperKnotInvitation: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let ruleID: String
    let bot: String
    let conversationID: String
    let title: String
    let state: String
    let createdAt: Double
    let expiresAt: Double
    let connectedAt: Double?
    let endedAt: Double?
    let delivery: String
    var expires: Date { Date(timeIntervalSince1970: expiresAt / 1000) }
    var canAnswer: Bool { state == "invited" && expires > Date() }
    var status: String {
        switch state {
        case "invited": expires > Date() ? "Invited" : "Missed"
        case "answered": connectedAt == nil ? "Answered · connecting" : "Connected"
        case "declined": "Declined"
        case "missed": "Missed"
        default: connectedAt == nil ? "Not connected" : "Ended"
        }
    }
}
nonisolated struct WhisperKnotIncomingAnswer: Sendable {
    let invitation: WhisperKnotInvitation
    let answerID: String
}
nonisolated struct WhisperKnotContactTarget: Identifiable, Sendable {
    let id = UUID()
    let bot: WhisperKnotBot
    let conversationID: UUID
    let invitation: WhisperKnotInvitation?
    var welcome: WhisperKnotWelcomeInvitation? = nil
}

/// Foreground reads discover real server invitations. Notifications merely
/// request a fresh authorized read; their payload cannot start a microphone.
@MainActor @Observable final class WhisperKnotContactService {
    static let shared = WhisperKnotContactService()
    private(set) var invitations: [WhisperKnotInvitation] = []
    var presentation: WhisperKnotContactTarget?
    private var generation = AccountStorage.generation
    private var blockedGeneration: UUID?
    private var refreshing = false
    private var hidden = Set<String>()
    private var pendingNotice: [String: String]?
    private var observer: NSObjectProtocol?
    private nonisolated struct Listing: Decodable, Sendable { let invitations: [WhisperKnotInvitation] }
    private nonisolated struct Result: Decodable, Sendable { let invitation: WhisperKnotInvitation? }
    private nonisolated struct Acknowledged: Decodable, Sendable { let ok: Bool }
    private nonisolated struct AnswerBody: Encodable { let answerID: String }
    private init() {
        observer = NotificationCenter.default.addObserver(forName: .init("WhisperMeetingAccountWillChange"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }
    private func reset() {
        blockedGeneration = AccountStorage.generation
        generation = UUID(); invitations = []; presentation = nil; hidden = []; pendingNotice = nil; refreshing = false
    }
    private func prepare() {
        guard blockedGeneration != AccountStorage.generation else { return }
        if generation != AccountStorage.generation {
            generation = AccountStorage.generation; blockedGeneration = nil
            invitations = []; presentation = nil; hidden = []; refreshing = false
            if pendingNotice?["recipient_user_id"]?.lowercased() != AccountStorage.currentUserID.lowercased() { pendingNotice = nil }
        }
    }
    func receive(_ info: [String: String]) {
        guard ["knot_update", "knot_invitation"].contains(info["kind"] ?? "") else { return }
        pendingNotice = info
        Task { await refresh() }
    }
    func withdrawCalls() async {
        AccountStorage.set(true, forKey: "knot_contact_calls_pause_pending_v1")
        let lease = AccountStorage.generation
        do {
            let result: Acknowledged = try await WhisperKnotBackgroundService.shared.contactRequest("/contact-revoke-calls", method: "POST")
            guard lease == AccountStorage.generation, result.ok else { return }
            AccountStorage.set(false, forKey: "knot_contact_calls_pause_pending_v1")
            await WhisperKnotBackgroundService.shared.refresh()
        } catch { /* The durable withdrawal remains pending for foreground retry. */ }
    }
    func refresh() async {
        prepare()
        guard generation == AccountStorage.generation, AccountStorage.currentUserID != "guest", AuthenticationService.shared.isSignedIn, !refreshing else { return }
        let lease = generation; refreshing = true
        defer { if generation == lease { refreshing = false } }
        do {
            if AccountStorage.bool(forKey: "knot_contact_calls_pause_pending_v1") {
                await withdrawCalls()
                guard lease == AccountStorage.generation, !AccountStorage.bool(forKey: "knot_contact_calls_pause_pending_v1") else { return }
            }
            let result: Listing = try await WhisperKnotBackgroundService.shared.contactRequest("/invitations")
            guard lease == AccountStorage.generation, !Task.isCancelled else { return }
            invitations = result.invitations
            if let notice = pendingNotice {
                pendingNotice = nil
                guard notice["recipient_user_id"]?.lowercased() == AccountStorage.currentUserID.lowercased() else { return }
                if notice["kind"] == "knot_invitation", let id = notice["invitation_id"], UUID(uuidString: id) != nil {
                    let result: Result = try await WhisperKnotBackgroundService.shared.contactRequest("/invitations/" + id)
                    guard lease == AccountStorage.generation, !Task.isCancelled, let invitation = result.invitation else { return }
                    show(invitation)
                } else if let bot = WhisperKnotBot(rawValue: notice["bot"] ?? ""), let id = UUID(uuidString: notice["conversation_id"] ?? "") {
                    await WhisperKnotBackgroundService.shared.syncMessages()
                    guard lease == AccountStorage.generation, !Task.isCancelled,
                          let conversation = WhisperEmberHistoryStore.shared.conversation(id), (conversation.botID ?? "main") == bot.rawValue else { return }
                    if presentation == nil { presentation = .init(bot: bot, conversationID: id, invitation: nil) }
                }
            } else if presentation == nil, WhisperKnotContextPermission.allowed, WhisperKnotVoicePreferences.allowed,
                      WhisperNotificationPrefs.isEnabled(.calls), !WhisperCameraCallMonitor.shared.callOwnsAudio, !WhisperKnotVoiceSession.isBusy,
                      let invitation = invitations.first(where: { $0.canAnswer && !hidden.contains($0.id) }) { show(invitation) }
        } catch { /* No fabricated call or notification after unavailable reads. */ }
    }
    func show(_ invitation: WhisperKnotInvitation) {
        guard presentation == nil, !WhisperCameraCallMonitor.shared.callOwnsAudio, !WhisperKnotVoiceSession.isBusy,
              let bot = WhisperKnotBot(rawValue: invitation.bot), let id = UUID(uuidString: invitation.conversationID) else { return }
        hidden.insert(invitation.id)
        presentation = .init(bot: bot, conversationID: id, invitation: invitation)
    }
    func current(_ invitation: WhisperKnotInvitation) -> WhisperKnotInvitation { invitations.first { $0.id == invitation.id } ?? invitation }
    func change(_ invitation: WhisperKnotInvitation, action: String, answerID: String = "") async throws -> WhisperKnotInvitation {
        guard ["answer", "decline", "connected", "end"].contains(action) else { throw CancellationError() }
        prepare(); let lease = generation
        let result: Result = try await WhisperKnotBackgroundService.shared.contactRequest("/invitations/\(invitation.id)/\(action)", method: "POST", body: JSONEncoder().encode(AnswerBody(answerID: answerID)))
        guard lease == AccountStorage.generation, let updated = result.invitation else { throw CancellationError() }
        invitations.removeAll { $0.id == updated.id }; invitations.insert(updated, at: 0)
        return updated
    }
    func read(_ invitation: WhisperKnotInvitation) async throws -> WhisperKnotInvitation {
        let lease = AccountStorage.generation
        let result: Result = try await WhisperKnotBackgroundService.shared.contactRequest("/invitations/" + invitation.id)
        guard lease == AccountStorage.generation, let current = result.invitation else { throw CancellationError() }
        return current
    }
}

struct WhisperKnotContactReview: View {
    let rule: WhisperKnotResponsibility
    @Environment(\.dismiss) private var dismiss
    @State private var service = WhisperKnotBackgroundService.shared
    @State private var push = false
    @State private var calls = false
    @State private var initialized = false
    @State private var ready = false
    @State private var notificationsAllowed = false
    @State private var voiceAllowed = WhisperKnotVoicePreferences.allowed
    @State private var epoch: String?
    @State private var approval: WhisperKnotContactApproval?
    @State private var attempted = false
    @State private var saving = false
    @State private var message: String?
    @State private var visible = false
    @State private var generation = AccountStorage.generation
    @State private var consentRevision = WhisperKnotContextPermission.revision
    private nonisolated struct Ready: Decodable, Sendable { let ready: Bool }
    private var leaseValid: Bool { visible && generation == AccountStorage.generation && consentRevision == WhisperKnotContextPermission.revision && WhisperKnotContextPermission.allowed }
    var body: some View {
        Form {
            Section(rule.title) {
                Toggle("Update notifications", isOn: $push)
                Toggle("Invite me to talk", isOn: $calls).disabled(!voiceAllowed)
                if !voiceAllowed, let bot = WhisperKnotBot(rawValue: rule.bot) {
                    NavigationLink("Review Voice & calls") { WhisperKnotVoiceSettingsView(bot: bot) }
                }
            }.disabled(attempted)
            Section("Exact limits") {
                LabeledContent("Checks", value: "\(rule.minIntervalMinutes)–\(rule.maxIntervalMinutes) minutes")
                LabeledContent("Call invitations", value: "At most one a day across Knots")
                LabeledContent("Time zone", value: rule.timezone)
                LabeledContent("Quiet hours", value: rule.quietStart == rule.quietEnd ? "None" : String(format: "%02d:00–%02d:00", rule.quietStart, rule.quietEnd))
                LabeledContent("Ends", value: rule.endDate.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                DisclosureGroup("Permission & privacy") {
                    Text("Contact is only about a real saved update for this exact responsibility. Notifications use a private generic preview. Whisper’s notification preferences still apply.")
                    Text("Call invitations expire after two minutes. Tap Answer inside Whisper to begin; nothing captures audio or connects automatically. Off-app invitations use ordinary notifications, not a phone-call ring screen.")
                    Text("After you answer, ElevenLabs handles live audio. The responsibility title, saved update and transcript pass through Whisper and Rork AI Cloud, via Vercel AI Gateway to OpenAI GPT‑4o, with your reply preferences and selected Boy or Girl voice. This is the same answering provider and model as text chat. No other conversations, profile or attachments are added. Calls cannot take actions. Separate call transcripts stay on this device.")
                    Text("Permission ends with this rule; pausing it or withdrawing sharing stops future invitations. Contact records expire after 30 days, up to 400 recent records. A content-free timestamp enforces the daily invitation limit across rule deletion and expires after 24 hours. Accepted by Apple does not mean delivered or read. A failed or ambiguous notification is not repeatedly sent.")
                }
                if !notificationsAllowed {
                    Button("Allow notifications") { Task { await WhisperNotificationService.shared.requestAuthorization(); await refreshNotificationPermission() } }.disabled(attempted)
                }
                if !ready { Text("Notification delivery isn’t available right now. Chat updates remain available.").foregroundStyle(.secondary) }
                if AccountStorage.bool(forKey: "knot_contact_calls_pause_pending_v1") {
                    Text("The pause for call invitations is awaiting confirmation. Existing server permissions may still send invitations until it is confirmed.").foregroundStyle(.secondary)
                    Button("Confirm pause") { Task { await WhisperKnotContactService.shared.withdrawCalls() } }
                }
                if let message { Text(message).foregroundStyle(.secondary) }
                if let error = service.error { Text(error).foregroundStyle(.secondary) }
            }
            Section {
                Button(saving ? "Saving…" : attempted ? "Retry exact approval" : "Approve contact permission") {
                    guard leaseValid, let epoch, !saving else { return }
                    if approval == nil { approval = .init(approvalID: UUID().uuidString.lowercased(), approvalEpoch: epoch, ruleRevision: rule.revision, push: push, calls: calls) }
                    guard let approval else { return }
                    attempted = true; saving = true
                    Task { @MainActor in
                        let success = await service.approveContact(approval, ruleID: rule.id)
                        saving = false
                        guard leaseValid else { return }
                        if success { Haptics.success(); dismiss() }
                    }
                }.disabled(saving || service.busy || epoch == nil || ((push || calls) && (!ready || !notificationsAllowed)) || (calls && (!voiceAllowed || AccountStorage.bool(forKey: "knot_contact_calls_pause_pending_v1"))))
            }
        }
        .navigationTitle("Contact permission").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving) } }
        .interactiveDismissDisabled(saving)
        .task {
            visible = true
            if !initialized {
                initialized = true; push = rule.contact?.push ?? false; calls = rule.contact?.calls ?? false
            }
            await service.refresh()
            guard leaseValid else { return }
            if service.rules.first(where: { $0.id == rule.id })?.revision == rule.revision {
                if !attempted { epoch = service.approvalEpoch }
            } else { epoch = nil; message = "This responsibility changed. Close and review it again." }
            let result: Ready? = try? await service.contactRequest("/contact-status")
            guard leaseValid else { return }; ready = result?.ready == true
            await refreshNotificationPermission()
        }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotVoiceConsentChanged"))) { _ in voiceAllowed = WhisperKnotVoicePreferences.allowed }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in dismiss() }
    }
    private func refreshNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard leaseValid else { return }
        notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
}
