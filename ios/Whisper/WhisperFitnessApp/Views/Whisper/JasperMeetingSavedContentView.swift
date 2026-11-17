import SwiftUI

struct JasperMeetingSavedContentView: View {
    let meetingID: String?
    @State private var answers: [JasperMeetingAnswer] = []
    @State private var documents: [WhisperNotebookDocument] = []
    @State private var error: String?
    @State private var jasperNote: WhisperNotebookDocument?
    @State private var recoveries: [WhisperNotebookDocument.Recovery] = []
    private let owner = AccountStorage.currentUserID.lowercased()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(answers) { answer in
                DisclosureGroup("Private Jasper notes · \(String(answer.generatedAt.prefix(10)))") { JasperMeetingAnswerView(answer: answer).padding(.vertical, 12) }.font(.subheadline)
            }
            if !documents.isEmpty {
                DisclosureGroup("Earlier private writing") {
                    Text("Your previous writing is preserved separately from the original shared notes.").font(.caption).foregroundStyle(.secondary)
                    ForEach(documents) { document in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(document.displayTitle).font(.headline)
                            Button("Ask Jasper about this", systemImage: "sparkles") { jasperNote = document }.frame(minHeight: 44)
                            Text(document.notes).font(.subheadline).textSelection(.enabled)
                            if !document.transcript.isEmpty { DisclosureGroup("Stored transcript excerpt") { Text(document.transcript).font(.caption).textSelection(.enabled) } }
                            if let result = document.enhancement {
                                DisclosureGroup("Earlier Jasper result") {
                                    ForEach(result.sections, id: \.title) { section in Text(section.title).font(.subheadline.weight(.medium)); ForEach(section.items, id: \.text) { Text($0.text).font(.caption) } }
                                }
                            }
                            if let data = try? JSONEncoder().encode(document), let text = String(data: data, encoding: .utf8) { ShareLink("Export original data", item: text).font(.caption).frame(minHeight: 44) }
                            Divider()
                        }.padding(.vertical, 10)
                    }
                }.font(.subheadline)
            }
            if !recoveries.isEmpty {
                DisclosureGroup("Earlier writing recovery") {
                    ForEach(recoveries) { recovery in
                        Text(recovery.document.displayTitle).font(.headline)
                        Text(recovery.document.notes).font(.subheadline).textSelection(.enabled)
                        if let data = try? JSONEncoder().encode(recovery.document), let text = String(data: data, encoding: .utf8) { ShareLink("Export recovery data", item: text).font(.caption).frame(minHeight: 44) }
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary); Button("Retry private additions") { Task { await load() } }.font(.caption).frame(minHeight: 44) }
        }.task { await load() }
        .sheet(item: $jasperNote) { note in WorkspaceNoteJasperView(noteID: note.id).id(note.id + owner) }
    }
    private func load() async {
        guard AccountStorage.currentUserID.lowercased() == owner else { return }
        do { documents = try WhisperNotebookStorage.load(ownerID: owner).filter { meetingID == nil || $0.meetingId == meetingID } }
        catch { self.error = "Earlier writing could not load. Existing files were not changed." }
        do { recoveries = try WhisperNotebookStorage.recoveries(ownerID: owner).filter { meetingID == nil || $0.document.meetingId == meetingID } } catch { self.error = "Some recovery data could not load. Existing files were not changed." }
        if let meetingID {
            do {
                struct History: Decodable { let answers: [JasperMeetingAnswer] }
                let history: History = try await JasperMeetingService.request("history?meetingId=\(meetingID)", owner: owner)
                guard AccountStorage.currentUserID.lowercased() == owner else { return }; answers = history.answers
            } catch { self.error = "Private Jasper additions could not load. Your original meeting notes remain available." }
        }
    }
}
