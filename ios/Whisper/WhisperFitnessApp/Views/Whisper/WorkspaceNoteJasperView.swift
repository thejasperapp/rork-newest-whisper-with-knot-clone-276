import SwiftUI

struct WorkspaceNoteJasperView: View {
    let noteID: String
    @Environment(\.dismiss) private var dismiss
    @State private var model: WhisperNotebookViewModel = WhisperNotebookViewModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let note = model.documents.first(where: { $0.id == noteID }), model.isCurrent {
                        Text(note.displayTitle).font(.title2.weight(.semibold))
                        WhisperNotebookQuestionsView(model: model, documents: [note])
                    } else if model.isLoading { ProgressView("Opening selected note…") }
                    else { ContentUnavailableView("Note unavailable", systemImage: "doc.text", description: Text("Refresh your private writing and try again.")) }
                }.padding(.horizontal, 16).padding(.vertical, 20)
            }
            .navigationTitle("Ask Jasper about this").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.load() }
            .onDisappear { model.cancelGeneration() }
        }
    }
}
