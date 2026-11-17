import SwiftUI

/// Recording status stays above presentations; approving is always an explicit action.
struct WhisperRecordingConsentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    private var consent: WhisperRecordingConsentService { .shared }

    var body: some View {
        @Bindable var consent = consent
        VStack(spacing: 8) {
            if consent.hasStatus {
                VStack(alignment: .leading, spacing: 6) {
                    if consent.requestID != nil {
                        HStack(spacing: 8) {
                            Image(systemName: consent.isRecording ? "record.circle.fill" : "mic.badge.plus")
                                .foregroundStyle(.red)
                            Text(consent.isRecording ? "\(consent.recorderName) is recording" : consent.accepted == true ? "Recording approved · waiting for host" : consent.accepted == false ? "Permission declined · awaiting host" : "Recording permission requested")
                                .font(.caption.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        if consent.accepted == nil {
                            Button("Review request") { consent.showPrompt = true }
                                .font(.caption.weight(.semibold)).frame(minHeight: 44)
                        } else if consent.accepted == true {
                            Button("Withdraw permission", role: .destructive) { consent.reply(false) }
                                .font(.caption.weight(.semibold)).frame(minHeight: 44)
                        }
                    }
                    if let notice = consent.notice { Text(notice).font(.caption).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(12)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.ink(colorScheme).opacity(0.15), lineWidth: 0.5) }
                .accessibilityElement(children: .contain)
            }
        }
        .sheet(isPresented: $consent.showPrompt, onDismiss: { if consent.accepted == nil { consent.reply(false) } }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: "record.circle").font(.largeTitle).foregroundStyle(.red)
                        Text("\(consent.recorderName) wants to record").font(.title2.bold())
                        Text(consent.includesVideo ? "Meeting voices, video and shared screen will be saved on the host’s browser and can be exported." : "Meeting voices will be saved on the host’s browser and can be exported.")
                        Text(consent.includesCloudArchive ? "The host also requests permission to save the recording, transcript and reviewed markers privately in their Whisper cloud account until they delete the backup. It is not automatically shared with attendees." : "Permanent cloud recording backup is not allowed by this request.")
                        Text(consent.includesCloudAI ? "Audio will also be sent to Whisper’s cloud AI provider for transcription. The host may ask Jasper to analyze the transcript and propose decisions." : "Cloud transcription and AI analysis are not enabled for this recording.")
                        Text("Everyone must allow it before recording starts. You can withdraw while recording. Going into the background withdraws your permission. App signaling cannot prevent recording outside Whisper.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("This is a recording made by the web host, not an iPhone recording. Allowing it does not give attendees a copy of the recording.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { consent.reply(true) } label: { Text("Allow recording").font(.headline).frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(.borderedProminent).tint(WhisperTheme.ink(colorScheme))
                        Button("Decline", role: .cancel) { consent.reply(false) }
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("Recording permission")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { consent.withdrawForBackground() } }
    }
}
