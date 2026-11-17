import SwiftUI

/// Keeps the viewer's reply/share state mounted while fresh access is rechecked.
struct WhisperReferencedStoryView: View {
    let storyID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var story: WhisperStoryRow?
    @State private var isLoading: Bool = true
    @State private var authorized: Bool = false
    @State private var failed: Bool = false
    @State private var attempt: Int = 0
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    private var suspended: Bool { !authorized || scenePhase != .active || closed }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story {
                WhisperStoryViewer(story: story, accessSuspended: suspended)
                    .opacity(suspended ? 0 : 1).accessibilityHidden(suspended)
            }
            if suspended {
                Color.black.ignoresSafeArea()
                if isLoading {
                    ProgressView("Opening story…").tint(.white).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label(failed ? "Couldn't open this story" : "Story unavailable", systemImage: "circle.dashed")
                    } description: {
                        Text(failed ? "Check your connection and try again." : "It may have expired, been deleted, or isn't shared with you.")
                    } actions: {
                        Button("Try again") { attempt += 1 }.buttonStyle(.borderedProminent)
                    }.foregroundStyle(.white)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if suspended {
                WhisperStoryControl(symbol: "xmark", label: "Close Story") { closed = true; dismiss() }.padding(16)
            }
        }
        .environment(\.colorScheme, .dark)
        .task(id: "\(attempt)|\(scenePhase == .active)") {
            guard scenePhase == .active, !closed, generation == AccountStorage.generation else { return }
            isLoading = true; failed = false; authorized = false
            do {
                let row = try await WhisperSharedStoryResolver.resolve(id: storyID)
                guard !Task.isCancelled, !closed, generation == AccountStorage.generation else { return }
                if let row { story = row; authorized = true }
                isLoading = false
                if let end = row.flatMap(WhisperSharedStoryResolver.expiry) {
                    try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
                    guard !Task.isCancelled, !closed, generation == AccountStorage.generation else { return }
                    authorized = false
                }
            } catch {
                guard !Task.isCancelled, !closed, generation == AccountStorage.generation else { return }
                isLoading = false; failed = true; authorized = false
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { authorized = false } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            closed = true; authorized = false; story = nil; dismiss()
        }
    }
}
