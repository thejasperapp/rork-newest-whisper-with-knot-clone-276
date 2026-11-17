import SwiftUI

nonisolated enum WhisperKnotCallVoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case boy, girl
    var id: String { rawValue }
    var title: String { self == .boy ? "Boy" : "Girl" }
}

@MainActor enum WhisperKnotVoicePreferences {
    static let consentVersion = "knot_rork_elevenlabs_voice_consent_v2"
    static var allowed: Bool { AccountStorage.bool(forKey: consentVersion) }
    static let relayConsentVersion = "knot_voice_chat_tools_v1"
    static var chatToolsAllowed: Bool { allowed && AccountStorage.bool(forKey: relayConsentVersion) }
    static func setChatToolsAllowed(_ value: Bool) {
        AccountStorage.set(value, forKey: relayConsentVersion)
        NotificationCenter.default.post(name: .init("WhisperKnotVoiceConsentChanged"), object: nil)
    }
    static var voice: WhisperKnotCallVoice {
        get { WhisperKnotCallVoice(rawValue: AccountStorage.string(forKey: "knot_call_voice_v1") ?? "") ?? .boy }
        set { AccountStorage.set(newValue.rawValue, forKey: "knot_call_voice_v1") }
    }
    static func setAllowed(_ value: Bool) {
        // A fresh base permission never revives a relay choice saved under the
        // earlier voice provider. Withdrawal clears it before notifying calls.
        if !value || !allowed { AccountStorage.set(false, forKey: relayConsentVersion) }
        AccountStorage.set(value, forKey: consentVersion)
        NotificationCenter.default.post(name: .init("WhisperKnotVoiceConsentChanged"), object: nil)
        if !value {
            let generation = AccountStorage.generation
            AccountStorage.set(true, forKey: "knot_contact_calls_pause_pending_v1")
            Task {
                guard generation == AccountStorage.generation else { return }
                await WhisperKnotContactService.shared.withdrawCalls()
            }
        }
    }
}

/// Separate from text-chat history. No raw audio, attachments or cross-bot memory.
nonisolated struct WhisperKnotCallRecord: Identifiable, Codable, Sendable {
    var id = UUID()
    let bot: WhisperKnotBot
    let voice: WhisperKnotCallVoice
    let startedAt: Date
    var connectedAt: Date?
    var endedAt: Date?
    var messages: [Line] = []
    var truncated = false
    var invitationID: String? = nil

    nonisolated struct Line: Identifiable, Codable, Sendable {
        let id: String
        let isUser: Bool
        let text: String
        let timestamp: Date
    }

    var duration: String {
        guard let connectedAt else { return "Not connected" }
        let seconds = max(0, Int((endedAt ?? connectedAt).timeIntervalSince(connectedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor @Observable final class WhisperKnotCallHistory {
    private static let key = "knot_call_transcripts_v1"
    private let generation = AccountStorage.generation
    private(set) var calls: [WhisperKnotCallRecord] = []
    private(set) var saveFailed = false

    init() {
        if let data = AccountStorage.data(forKey: Self.key), data.count <= 2_000_000,
           let records = try? JSONDecoder().decode([WhisperKnotCallRecord].self, from: data) {
            calls = Array(records.sorted { $0.startedAt > $1.startedAt }.prefix(40))
        }
    }

    func save(_ call: WhisperKnotCallRecord) {
        guard generation == AccountStorage.generation, AccountStorage.currentUserID != "guest" else { return }
        calls.removeAll { $0.id == call.id }
        calls.insert(call, at: 0)
        persist()
    }

    func delete(_ id: UUID) {
        guard generation == AccountStorage.generation else { return }
        calls.removeAll { $0.id == id }; persist()
    }

    func clearMemory() { calls = [] }

    private func persist() {
        calls = Array(calls.sorted { $0.startedAt > $1.startedAt }.prefix(40))
        do {
            var data = try JSONEncoder().encode(calls)
            while data.count > 2_000_000, calls.count > 1 {
                calls.removeLast(); data = try JSONEncoder().encode(calls)
            }
            guard data.count <= 2_000_000 else { saveFailed = true; return }
            AccountStorage.set(data, forKey: Self.key)
            saveFailed = false
        } catch { saveFailed = true }
    }
}

struct WhisperKnotVoiceSettingsView: View {
    let bot: WhisperKnotBot
    var forCall = false
    var onAgree: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var selected = WhisperKnotVoicePreferences.voice
    @State private var allowed = WhisperKnotVoicePreferences.allowed
    @State private var chatToolsAllowed = WhisperKnotVoicePreferences.chatToolsAllowed
    @State private var generation = AccountStorage.generation

    var body: some View {
        Form {
            Section {
                Picker("Knot’s voice", selection: $selected) {
                    ForEach(WhisperKnotCallVoice.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("Your preference applies to all five Knots on this device. A voice change takes effect on your next call.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Choose a voice") }
            Section {
                Text("ElevenLabs handles live audio, speech recognition and playback. Transcripts and answers pass through Whisper’s server, Rork AI Cloud and Vercel AI Gateway to OpenAI GPT-4o. ElevenLabs does not choose a separate answering model. Reply preferences are included. This Knot’s recent text conversation is included only while AI sharing is on; your Whisper profile is included only if you enabled it in Privacy & context. Other Knots’ chats and attachments are not included.")
                Text("Whisper does not save call audio. Before a call can start, the voice agent must have audio recording off and conversation history set to expire after one day. Provider processing, derived data, security records and backups follow its policies and may be kept longer; this is not a zero-retention service.")
                Text("A separate text transcript stays with your account on this device, up to 40 recent calls and 2 MB. Open or delete it in Call transcripts. Without chat tools, spoken messages are not added to text chat. With chat tools, finalized requests and answers also appear there. Transcripts can contain recognition errors and text that was interrupted before it finished playing.")
                Text("With chat tools enabled, finalized speech is sent through Knot’s Rork AI Cloud chat service and existing tools, using OpenAI GPT-4o. Requests and answers are saved in this Knot’s text conversation. Only the final answer—not command logs or raw receipts—is returned to ElevenLabs to speak. Public browser requests use Knot’s browser; workspace commands use its existing executor. End call and interruptions stop owned work, without replaying uncertain actions. Changes in Whisper and Responsibilities still require their exact native review in chat. Welcome and invitation calls keep their separate, narrower permissions.")
                Text("Calls stay on OpenAI GPT-4o even if you separately enable task-specific Claude models for private text. Tool access is a separate choice below; agreeing to a call does not enable it automatically. The new sharing choice replaces the earlier direct-provider voice permission.").font(.footnote).foregroundStyle(.secondary)
                Link("ElevenLabs privacy policy", destination: URL(string: "https://elevenlabs.io/privacy-policy")!)
                Link("OpenAI privacy policy", destination: URL(string: "https://openai.com/policies/privacy-policy/")!)
                Link("Vercel AI Gateway privacy", destination: URL(string: "https://vercel.com/docs/ai-gateway/capabilities/privacy-and-compliance")!)
            } header: { Label("Before you call", systemImage: "hand.raised") }
            if forCall {
                Section {
                    Toggle("Use chat tools in conversation calls", isOn: $chatToolsAllowed)
                    Text("Optional. This also saves finalized requests and answers in this Knot’s text chat. Account changes still need exact review there.").font(.footnote).foregroundStyle(.secondary)
                    Button("Agree & call \(bot.displayName)") {
                        guard generation == AccountStorage.generation else { return }
                        WhisperKnotVoicePreferences.voice = selected
                        WhisperKnotVoicePreferences.setAllowed(true)
                        WhisperKnotVoicePreferences.setChatToolsAllowed(chatToolsAllowed)
                        onAgree(); dismiss()
                    }.fontWeight(.semibold)
                    Button("Not now", role: .cancel) { dismiss() }
                }
            } else {
                Section {
                    Toggle("Save Rork & ElevenLabs call permission", isOn: $allowed)
                    Toggle("Use chat tools in conversation calls", isOn: $chatToolsAllowed).disabled(!allowed)
                    if AccountStorage.bool(forKey: "knot_contact_calls_pause_pending_v1") {
                        Text("Call invitation withdrawal is awaiting server confirmation. Previously approved invitations may still arrive until it is confirmed.")
                        Button("Confirm invitation withdrawal") { Task { await WhisperKnotContactService.shared.withdrawCalls() } }
                    }
                    Text("Turning this off ends an active Knot call, disables saved chat-tool permission and requests withdrawal of approved incoming invitations. An outgoing Call tap starts only that call; it does not save permission for incoming invitations or chat tools. Microphone access is controlled by iOS. This cannot retract information already sent. Deleting a local transcript does not delete the provider’s copy.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Call transcripts") { WhisperKnotCallHistoryView(bot: bot) }
                }
            }
        }
        .navigationTitle("Voice & calls").navigationBarTitleDisplayMode(.inline)
        .onChange(of: selected) { _, value in
            guard !forCall, generation == AccountStorage.generation else { return }
            WhisperKnotVoicePreferences.voice = value
        }
        .onChange(of: chatToolsAllowed) { _, value in
            guard !forCall, generation == AccountStorage.generation else { return }
            WhisperKnotVoicePreferences.setChatToolsAllowed(value)
        }
        .onChange(of: allowed) { _, value in
            guard !forCall, generation == AccountStorage.generation else { return }
            WhisperKnotVoicePreferences.setAllowed(value)
            chatToolsAllowed = WhisperKnotVoicePreferences.chatToolsAllowed
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
    }
}

struct WhisperKnotCallHistoryView: View {
    let bot: WhisperKnotBot
    @State private var history = WhisperKnotCallHistory()
    @State private var deleting: UUID?
    @Environment(\.dismiss) private var dismiss

    private var calls: [WhisperKnotCallRecord] { history.calls.filter { $0.bot == bot } }
    var body: some View {
        List {
            Section {
                Text("\(bot.displayName)’s call transcripts are saved as text on this device. Up to 40 calls across your Knots, within 2 MB. With chat tools enabled, finalized requests and answers are also saved in your text conversation.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if calls.isEmpty {
                ContentUnavailableView("No calls yet", systemImage: "phone", description: Text("Your calls with \(bot.displayName) will appear here."))
            }
            ForEach(calls) { call in
                NavigationLink {
                    WhisperKnotCallTranscriptView(call: call)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: call.invitationID == nil ? "phone.arrow.up.right" : "phone.arrow.down.left").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(call.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.headline)
                            Text("\(call.duration) · \(call.voice.title) voice").font(.caption).foregroundStyle(.secondary)
                            if let text = call.messages.last?.text { Text(text).font(.subheadline).lineLimit(2).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 5)
                }
                .swipeActions { Button("Delete", role: .destructive) { deleting = call.id } }
            }
        }
        .navigationTitle("Call transcripts").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this call transcript from this device?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete transcript", role: .destructive) { if let deleting { history.delete(deleting) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in history.clearMemory(); dismiss() }
    }
}

struct WhisperKnotCallTranscriptView: View {
    let call: WhisperKnotCallRecord
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(call.bot.displayName).font(.title2.bold())
                    Text(call.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary)
                    Text("AI call · \(call.duration) · \(call.voice.title) voice").font(.caption).foregroundStyle(.secondary)
                }
                if call.messages.isEmpty { Text("No transcript was received for this call.").foregroundStyle(.secondary) }
                ForEach(call.messages) { line in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.isUser ? "You" : call.bot.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(line.text).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(call.truncated ? "This transcript reached its local size limit. Some later text was not saved." : "Transcripts may contain recognition errors or interrupted speech. This is text, not an audio recording.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: 620, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
        .navigationTitle("Transcript").navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
    }
}
