import SwiftUI

/// One independent comments placement, never counted in the thread's comment total.
struct WhisperCommentAdView: View {
    let threadID: String
    var isActive: Bool = true
    @State private var service: WhisperFeedAdService = WhisperFeedAdService(placement: .comments)
    @State private var isVisible: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let ad = service.ads.first {
                WhisperSponsoredAdCard(ad: ad, service: service, isFeedActive: isActive && isVisible)
                    .id("\(threadID)-\(ad.id)")
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: threadID) { await service.refresh(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: .whisperAccountSwitched)) { _ in
            service.resetForCurrentAccount()
            Task { await service.refresh(force: true) }
        }
    }
}
