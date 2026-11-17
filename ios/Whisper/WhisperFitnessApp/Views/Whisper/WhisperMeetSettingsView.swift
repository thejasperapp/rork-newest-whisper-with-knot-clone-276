import SwiftUI

struct WhisperMeetSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("whisper_meet_default_mic") private var mic: Bool = true
    @AppStorage("whisper_meet_default_camera") private var camera: Bool = true
    @State private var effects: Bool = false
    var body: some View {
        NavigationStack {
            Form {
                Section("When joining") {
                    Toggle("Microphone on", isOn: $mic)
                    Toggle("Camera on", isOn: $camera)
                    Text("Defaults for this device. You can change both in the lobby before joining.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Video") { Button("Backgrounds & effects") { effects = true } }
                Section("Permissions & captions") {
                    Text("Captions use your microphone and Speech Recognition permission. If captions pause after changing headphones, use Retry in the transcript panel. Your call can continue without captions.")
                    Button("Open device settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
            }.navigationTitle("Meeting settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.sheet(isPresented: $effects) { WhisperVideoEffectsSheet() }
    }
}
