import SwiftUI

/// Financial access stays available without reopening Creator Studio.
struct WhisperCreatorPayoutsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var reloadID: UUID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your payouts, in one place.").font(.title2.bold())
                    Text("Review your paid-partner earnings and manage your payout account.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    WhisperWppCard().id(reloadID)
                    Button("Reload earnings", systemImage: "arrow.clockwise") { reloadID = UUID() }
                        .frame(minHeight: 44)
                }
                .padding(16)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Creator payouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
            .whisperEdgeBack { dismiss() }
        }
    }
}
