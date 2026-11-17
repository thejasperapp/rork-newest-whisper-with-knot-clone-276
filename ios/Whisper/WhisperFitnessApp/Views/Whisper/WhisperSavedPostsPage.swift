import SwiftUI

struct WhisperSavedPostsPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var rows: [WhisperPostRow] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var loadOperation = UUID()
    @State private var selectedPost: WhisperPostRow?
    @State private var bookmarks = WhisperBookmarkService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                        Button("Try again") { Task { await load() } }.frame(minHeight: 44)
                    }
                    WhisperSavedCollectionsView(rows: rows, loading: isLoading, onOpen: { selectedPost = $0 })
                }.padding(.vertical, 16)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
            .task(id: AccountStorage.generation) { await load() }
            .onDisappear { loadOperation = UUID() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                loadOperation = UUID(); rows = []; selectedPost = nil; dismiss()
            }
            .onChange(of: bookmarks.bookmarkedPostIDs) { old, new in
                let removed = old.subtracting(new)
                rows.removeAll { removed.contains($0.id) }
            }
            .whisperRefreshable { await load() }
            .fullScreenCover(item: $selectedPost) { row in
                WhisperPostDetailView(post: WhisperRootView.mapRowToPost(row))
            }
            .whisperEdgeBack { dismiss() }
        }
    }

    private func load() async {
        let generation = AccountStorage.generation, operation = UUID()
        loadOperation = operation
        isLoading = true
        defer { if generation == AccountStorage.generation, operation == loadOperation { isLoading = false } }
        do {
            let loaded = try await WhisperBookmarkService.shared.loadBookmarkedPosts()
            guard !Task.isCancelled, generation == AccountStorage.generation, operation == loadOperation else { return }
            rows = loaded
            errorMessage = nil
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, operation == loadOperation else { return }
            errorMessage = "Saved posts couldn’t be loaded. Your bookmarks are still saved."
        }
    }
}
