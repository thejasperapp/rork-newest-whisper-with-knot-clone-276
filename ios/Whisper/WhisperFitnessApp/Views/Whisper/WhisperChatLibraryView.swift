import SwiftUI

/// Searches the loaded conversation without altering its chronological message runs.
struct WhisperChatLibraryView: View {
    let messages: [WhisperMessageRow]
    let onSelect: (String) -> Void
    var initialScope: String = "Messages"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var query: String = ""
    @State private var scope: String = "Messages"
    private let scopes: [String] = ["Messages", "Media", "Links"]

    private var results: [WhisperMessageRow] {
        messages.reversed().filter { message in
            let video = WhisperDMThreadView.videoURL(in: WhisperChatReply.split(message.body).text)
            let image = WhisperDMThreadView.imageURL(in: WhisperChatReply.split(message.body).text)
            let matchesScope = scope == "Messages" || (scope == "Media" && (video != nil || image != nil)) ||
                (scope == "Links" && video == nil && image == nil && message.body.contains("http"))
            return matchesScope && (query.isEmpty || message.from_username.localizedStandardContains(query) ||
                WhisperChatReply.quoteText(for: message.body).localizedStandardContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Search in", selection: $scope) {
                    ForEach(scopes, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(16)
                List {
                    Section {
                        if results.isEmpty {
                            WhisperEmptyState(icon: "magnifyingglass", title: query.isEmpty ? "No shared content here yet" : "No matching messages", message: "Try another search. Only messages loaded on this device are included.", isCard: false, compact: true)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(results) { message in
                            Button {
                                onSelect(message.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    if let image = WhisperDMThreadView.imageURL(in: WhisperChatReply.split(message.body).text) {
                                        Color(.secondarySystemBackground).frame(width: 52, height: 52)
                                            .overlay { WhisperCachedAsyncImage(url: image) { phase in
                                                if case .success(let picture) = phase { picture.resizable().scaledToFill() }
                                            }.allowsHitTesting(false) }
                                            .clipShape(.rect(cornerRadius: 10))
                                    } else if WhisperDMThreadView.videoURL(in: WhisperChatReply.split(message.body).text) != nil {
                                        Image(systemName: "play.rectangle.fill").font(.title2).frame(width: 52, height: 52)
                                    }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("@\(message.from_username)").font(.caption.weight(.semibold))
                                        Text(WhisperChatReply.quoteText(for: message.body)).font(.subheadline).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.left").font(.caption)
                                }
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .frame(minHeight: 52)
                            }
                        }
                    } footer: { Text("Searches messages currently loaded on this device. Tap a result to return to it in the conversation.") }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            }
            .onAppear { scope = initialScope }
            .navigationTitle("Search & shared media")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Message or sender")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
