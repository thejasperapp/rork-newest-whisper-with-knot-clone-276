import SwiftUI

/// A selected-meeting entry; opening and prefilling never submit a question.
struct WorkspaceMeetingJasperView: View {
    let meeting: WhisperMeetingRow
    @State private var model: JasperMeetingsViewModel = JasperMeetingsViewModel()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            JasperMeetingAssistantView(model: model, meetingID: meeting.id, embedded: true)
                .navigationTitle(meeting.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.onDisappear { model.stop() }
    }
}
