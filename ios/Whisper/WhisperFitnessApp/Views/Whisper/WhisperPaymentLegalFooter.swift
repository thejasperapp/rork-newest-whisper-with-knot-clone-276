import SwiftUI

struct WhisperPaymentLegalFooter: View {
    var body: some View {
        HStack(spacing: 22) {
            if let terms = URL(string: "https://www.mydailywhisper.com/terms") {
                Link("Terms", destination: terms).frame(minHeight: 44)
            }
            if let privacy = URL(string: "https://www.mydailywhisper.com/privacy") {
                Link("Privacy", destination: privacy).frame(minHeight: 44)
            }
        }
        .font(.caption)
        .tint(.primary)
        .frame(maxWidth: .infinity)
    }
}
