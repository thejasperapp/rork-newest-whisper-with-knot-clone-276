import SwiftUI

/// Inbox-style list of pending follow requests for the current (private)
/// account. Each row has Approve / Deny CTAs that flip the request and,
/// on approval, insert the follow row server-side.
struct WhisperFollowRequestsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var requests = WhisperFollowRequestService.shared
    @State private var working: Set<String> = []
    /// Requester profiles so rows render real avatars instead of initials.
    @State private var profiles: [String: WhisperBackendService.WhisperPublicProfile] = [:]

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if requests.incoming.isEmpty {
                        WhisperEmptyState(
                            icon: "person.crop.circle.badge.questionmark",
                            title: "No follow requests",
                            message: "When someone wants to follow your private account, they'll show up here."
                        )
                        .padding(.top, 80)
                    } else {
                        ForEach(requests.incoming) { req in
                            row(req)
                            Rectangle()
                                .fill(WhisperTheme.hairline(colorScheme))
                                .frame(height: 0.5)
                                .padding(.leading, 76)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Follow requests")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await requests.refresh()
            await hydrateProfiles()
        }
        .whisperRefreshable {
            await requests.refresh()
            await hydrateProfiles()
        }
    }

    private func hydrateProfiles() async {
        let ids = requests.incoming.map { $0.requester_id }
            .filter { profiles[$0] == nil }
        guard !ids.isEmpty else { return }
        let map = await WhisperBackendService.shared.fetchPublicProfiles(userIDs: ids)
        for (uid, profile) in map { profiles[uid] = profile }
    }

    @ViewBuilder
    private func row(_ req: WhisperFollowRequestRow) -> some View {
        let busy = working.contains(req.id)
        let profile = profiles[req.requester_id]
        HStack(spacing: 12) {
            WhisperAvatar(
                username: profile?.username ?? req.requester_username,
                size: 48,
                imageURL: profile?.profile_image_url.flatMap { URL(string: $0) }
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(profile?.username ?? req.requester_username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Wants to follow you")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Button {
                    Haptics.success()
                    decide(req, approve: true)
                } label: {
                    Text("Confirm")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button {
                    Haptics.tap()
                    decide(req, approve: false)
                } label: {
                    Text("Delete")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            .opacity(busy ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func decide(_ req: WhisperFollowRequestRow, approve: Bool) {
        working.insert(req.id)
        Task {
            if approve {
                _ = await requests.approve(req)
            } else {
                _ = await requests.deny(req)
            }
            await MainActor.run { working.remove(req.id) }
        }
    }
}
