import SwiftUI

struct JasperMeetingSourceView: View {
    let evidence: JasperMeetingAnswer.Evidence
    @Environment(\.dismiss) private var dismiss
    @State private var meeting: WhisperMeetingRow?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(evidence.meetingTitle).font(.title2.weight(.semibold))
                    Text("\(evidence.speaker) · \(evidence.spokenAt)").font(.caption).foregroundStyle(.secondary)
                    if evidence.kind == "summary" { Text("Saved notes · summary, not verbatim speech").font(.caption).foregroundStyle(.secondary) }
                    if let position = evidence.position { Text("Private recording · \(WhisperRecordingArchive.time(position))\(evidence.timing == "chunk" ? " · Approximate range" : "")").font(.caption).foregroundStyle(WhisperBrandGradient.rose) }
                    Text(evidence.text).font(.body).textSelection(.enabled)
                    Text("Exact saved quotation · excerpt starts at character \(evidence.offset + 1)").font(.caption2).foregroundStyle(.secondary)
                    Button("Open original meeting notes") {
                        Task {
                            if let row = await WhisperMeetingService.shared.fetchArchived(id: evidence.meetingId) { meeting = row }
                            else { error = "This meeting could not be opened. Your access may have changed." }
                        }
                    }.buttonStyle(.bordered).controlSize(.large)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }.navigationTitle("Source quotation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.overlay { if let meeting { WhisperMeetingNotesView(meeting: meeting, onClose: { self.meeting = nil }) } }
    }
}
