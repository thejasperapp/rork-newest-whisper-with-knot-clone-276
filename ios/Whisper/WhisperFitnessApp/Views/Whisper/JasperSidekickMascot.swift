import SwiftUI

/// The regular animated Jasper, shared with the rest of Whisper.
struct JasperSidekickMascot: View {
    var size: CGFloat = 56
    var isWorking: Bool = false

    var body: some View {
        WhisperEmberMascot(size: size, isActive: isWorking, expression: isWorking ? .thinking : .calm)
            .accessibilityLabel("Jasper")
    }
}
