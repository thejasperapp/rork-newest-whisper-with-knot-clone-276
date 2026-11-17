import Foundation
import Observation
import Supabase

@MainActor @Observable
final class WhisperNotebookQuestionsViewModel {
    private(set) var answer: WhisperNotebookDocument.Result?
    private(set) var sources: [WhisperNotebookDocument] = []
    private(set) var isGenerating: Bool = false
    private(set) var errorText: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    private var operation: UUID = UUID()

    func cancelPending() {
        operation = UUID(); task?.cancel(); task = nil; isGenerating = false; errorText = nil
    }

    func reset() {
        operation = UUID(); task?.cancel(); task = nil
        isGenerating = false; answer = nil; sources = []; errorText = nil
    }

    func ask(documents: [WhisperNotebookDocument], question: String, workflow: WhisperNotebookWorkflow = .ask) {
        guard !isGenerating, (workflow != .ask || !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), question.count <= 600 else { return }
        reset()
        let owner = AccountStorage.currentUserID.lowercased(), generation = AccountStorage.generation, token = operation
        do { _ = try WhisperNotebookIntelligence.selectionSources(owner: owner, documents: documents) }
        catch { errorText = error.localizedDescription; return }
        isGenerating = true
        sources = documents
        task = Task { [weak self] in
            guard let self else { return }
            defer { if operation == token { isGenerating = false; task = nil } }
            @MainActor func check() throws {
                guard !Task.isCancelled, self.operation == token, AuthenticationService.shared.isSignedIn,
                      AccountStorage.generation == generation, AccountStorage.currentUserID.lowercased() == owner,
                      SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == owner else { throw WhisperNotebookError.accountChanged }
            }
            func checkSources() throws {
                let current = try WhisperNotebookStorage.load(ownerID: owner)
                guard documents.allSatisfy({ snapshot in current.contains { $0.id == snapshot.id && $0.storageRevision == snapshot.storageRevision } }) else { throw WhisperNotebookError.conflict }
            }
            do {
                try check(); try checkSources()
                let session = try await SupabaseService.shared.client.auth.session
                try check()
                guard session.user.id.uuidString.lowercased() == owner, let first = documents.first else { throw WhisperNotebookError.accountChanged }
                let passages = try WhisperNotebookIntelligence.selectionSources(owner: owner, documents: documents)
                let result = try await WhisperNotebookIntelligence.generate(document: first, question: question, toolkitURL: Config.allValues["EXPO_PUBLIC_TOOLKIT_URL"] ?? "https://toolkit.rork.com", secret: Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? "", selectedSources: passages, workflow: workflow)
                try check(); try checkSources()
                answer = result
            } catch {
                guard operation == token, !Task.isCancelled, AccountStorage.generation == generation else { return }
                errorText = (error as? WhisperNotebookError)?.localizedDescription ?? WhisperNotebookError.unavailable.localizedDescription
            }
        }
    }
}
