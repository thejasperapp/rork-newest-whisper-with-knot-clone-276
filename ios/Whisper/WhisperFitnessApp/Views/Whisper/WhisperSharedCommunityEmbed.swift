import SwiftUI

/// Catalog identity only: sharing never grants membership or embeds private posts.
nonisolated enum WhisperSharedCommunityEmbed {
    static let prefix = "::whisper-sharedcommunity-v1::"
    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let communityID: String
        var id: String { communityID }
    }
    static func community(for payload: Payload) -> WhisperCommunity? {
        WhisperCommunity.catalog.first { $0.id == payload.communityID }
    }
    static func encode(_ payload: Payload) -> String {
        guard community(for: payload) != nil, let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }
    static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix), body.utf8.count <= 2048,
              let data = String(body.dropFirst(prefix.count)).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              community(for: payload) != nil else { return nil }
        return payload
    }
}

struct WhisperSharedCommunityInlineCard: View {
    let payload: WhisperSharedCommunityEmbed.Payload
    let mine: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var showingCommunity = false
    @State private var sharing = false
    var body: some View {
        if let community = WhisperSharedCommunityEmbed.community(for: payload) {
            Button { showingCommunity = true } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Shared community", systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Image(systemName: community.symbol).font(.title2)
                            .frame(width: 50, height: 50)
                            .background(LinearGradient(colors: community.gradient, startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 14))
                        Text(community.name).font(.headline).lineLimit(2)
                    }
                    Text(community.tagline).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    Label("View community", systemImage: "arrow.up.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.ink(scheme)).padding(16).frame(width: 250, alignment: .leading)
                .background(WhisperTheme.card(scheme), in: .rect(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(WhisperTheme.hairline(scheme), lineWidth: 0.75) }
            }
            .buttonStyle(.plain)
            .contextMenu { Button("Share in a message", systemImage: "paperplane") { sharing = true } }
            .sheet(isPresented: $showingCommunity) {
                VStack(spacing: 0) {
                    HStack { Spacer(); Button("Done") { showingCommunity = false }.padding() }
                    NavigationStack { WhisperCommunityDetailView(community: community) }
                }
            }
            .sheet(isPresented: $sharing) {
                WhisperRecipientShareSheet(payload: WhisperSharedCommunityEmbed.encode(payload)) { EmptyView() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                showingCommunity = false; sharing = false
            }
        } else {
            Text("This community is unavailable").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
