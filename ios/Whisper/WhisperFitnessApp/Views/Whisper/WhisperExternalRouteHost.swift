import SwiftUI
import UIKit

/// A single presenter for widget and message routes; never dismisses another editor to make room.
struct WhisperExternalRouteHost: ViewModifier {
    let ready: Bool
    let selectTab: (Int) -> Void
    @State private var routes: WhisperExternalRouteStore = .shared
    @State private var presented: WhisperExternalRouteStore.Request?
    @State private var group: WhisperGroup?
    @State private var thread: WhisperConversationSummary?
    @State private var storyRows: [WhisperStoryRow] = []
    @State private var issue: String?
    @State private var retry: WhisperExternalRouteStore.Request?

    func body(content: Content) -> some View {
        content
            .task(id: "\(ready)-\(routes.pending?.id.uuidString ?? "none")") {
                guard ready, let request = routes.pending else { return }
                // This is a readiness check, not a delayed fire-and-forget presentation.
                while !Task.isCancelled, routes.pending?.id == request.id {
                    if canPresent { await open(request); if routes.pending?.id != request.id { return } }
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
            }
            .fullScreenCover(item: $presented, onDismiss: { routes.isPresenting = false }) { request in
                destination(request)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                presented = nil; group = nil; thread = nil; storyRows = []; issue = nil; retry = nil
            }
            .alert("Couldn't open this link", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
                if let retry { Button("Try again") { issue = nil; routes.enqueue(retry) } }
                Button("OK", role: .cancel) { issue = nil; retry = nil }
            } message: { Text(issue ?? "Please try again.") }
    }

    private var canPresent: Bool {
        guard presented == nil, UIApplication.shared.applicationState == .active,
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow),
              let root = window.rootViewController else { return false }
        return root.presentedViewController == nil && root.transitionCoordinator == nil
    }

    @ViewBuilder private func destination(_ request: WhisperExternalRouteStore.Request) -> some View {
        switch request.kind {
        case "dm":
            if let thread { WhisperDMThreadView(otherUserID: thread.otherUserID, otherUsername: thread.otherUsername, conversationKind: thread.kind) }
        case "group":
            if let group { WhisperGroupChatView(group: group) }
        case "knot", "jasper": WhisperEmberChatView()
        case "imagine": WhisperImagineDestinationView()
        case "thought": WhisperThoughtComposerView()
        case "calendar": WhisperCalendarView()
        case "coach": WhisperCoachClientsView()
        case "activity": WhisperInboxView(initialTab: .activity, activityOnly: true)
        case "stories": WhisperStoryViewer(stories: storyRows, startIndex: WhisperStoryService.shared.firstUnseenIndex(in: storyRows))
        default: EmptyView()
        }
    }

    private func open(_ request: WhisperExternalRouteStore.Request) async {
        let owner = AccountStorage.currentUserID.lowercased()
        let generation = AccountStorage.generation
        guard request.owner == nil || request.owner?.lowercased() == owner else {
            routes.pending = nil; issue = "This link belongs to another account. Switch to that account, then tap the notification or widget again."; return
        }
        if request.kind == "dm", ["knot", "ember", "jasper"].contains(request.userID.lowercased()) || (request.userID.isEmpty && ["knot", "ember", "jasper"].contains(request.username.lowercased())) {
            routes.pending = nil
            routes.isPresenting = true
            presented = .init(kind: "jasper", owner: request.owner)
            return
        }
        var resolvedThread: WhisperConversationSummary?
        var resolvedGroup: WhisperGroup?
        var resolvedStories: [WhisperStoryRow] = []
        if request.kind == "dm" {
            if UUID(uuidString: request.userID) != nil {
                if let profile = await WhisperBackendService.shared.fetchPublicProfile(userID: request.userID) {
                    resolvedThread = WhisperConversationSummary(otherUserID: request.userID, otherUsername: profile.username ?? request.username, lastMessage: "", lastDate: Date(), kind: .resolve(threadID: request.threadID, first: owner, second: request.userID))
                }
            } else if let profile = await WhisperUserService.shared.fetchByUsername(request.username) {
                resolvedThread = WhisperConversationSummary(otherUserID: profile.user_id, otherUsername: profile.username ?? request.username, lastMessage: "", lastDate: Date(), kind: .resolve(threadID: request.threadID, first: owner, second: profile.user_id))
            }
        } else if request.kind == "group", let id = UUID(uuidString: request.userID) {
            await WhisperGroupChatService.shared.syncRegistry(force: true)
            let groups = WhisperGroupChatService.shared
            if groups.lastError == nil, groups.activeRegistryIDs.contains(id) {
                resolvedGroup = groups.visibleGroups.first { $0.id == id }
            }
        } else if request.kind == "stories" {
            await WhisperStoryService.shared.fetch()
            let groups = WhisperStoryService.shared.storiesByUser()
            let selected = request.userID.isEmpty ? groups.first(where: { $0.all.first?.user_id.lowercased() != owner }) : groups.first(where: { $0.all.first?.user_id.lowercased() == request.userID.lowercased() })
            resolvedStories = selected.map { Array($0.all.reversed()) } ?? []
        }
        guard !Task.isCancelled, generation == AccountStorage.generation, routes.pending?.id == request.id else { return }
        guard canPresent else { return }
        routes.pending = nil
        if request.kind == "dm" && resolvedThread == nil || request.kind == "group" && resolvedGroup == nil || request.kind == "stories" && resolvedStories.isEmpty {
            retry = request
            issue = request.kind == "stories" ? "There are no available stories right now." : "This conversation isn't available. Check your connection and access, then try again."
            return
        }
        if request.kind == "inbox" { selectTab(2); return }
        group = resolvedGroup; thread = resolvedThread; storyRows = resolvedStories
        routes.isPresenting = true
        presented = request
    }
}
