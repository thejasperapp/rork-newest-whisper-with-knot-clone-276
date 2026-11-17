import SwiftUI

/// Profile photos use the same focal pinch and inertial pan as post/chat photos.
struct WhisperAvatarZoomView: View {
    let username: String
    var imageURL: URL? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isZoomed = false
    @State private var dragDismiss: CGFloat = 0

    private var resolvedURL: URL? {
        if let imageURL { return imageURL }
        let me = (LeaderboardService.shared.savedUsername
                  ?? AuthenticationService.shared.currentUser.username ?? "").lowercased()
        if me == username.lowercased(),
           let raw = AuthenticationService.shared.currentUser.profileImageURL,
           let url = URL(string: raw) { return url }
        return WhisperBackendService.shared.avatarURLString(forUsername: username.lowercased()).flatMap(URL.init(string:))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                Group {
                    if let url = resolvedURL {
                        WhisperPostPhotoPage(url: url, isActive: true,
                                             onZoomChanged: { zoomed in
                                                 isZoomed = zoomed
                                                 if zoomed { dragDismiss = 0 }
                                             }, onDismiss: { dismiss() })
                    } else {
                        WhisperAvatar(username: username, size: max(1, min(geometry.size.width, geometry.size.height) - 48))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .offset(y: dragDismiss)
                .simultaneousGesture(dismissDrag)
            }
            .overlay(alignment: .top) {
                HStack {
                    Text("@\(username)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.white.opacity(0.12), in: Capsule())
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white).frame(width: 34, height: 34)
                            .background(.white.opacity(0.14), in: Circle())
                            .frame(width: 44, height: 44).contentShape(.rect)
                    }
                    .accessibilityLabel("Close profile photo")
                }
                .padding(.horizontal, 16).padding(.top, 10)
            }
            .overlay(alignment: .bottom) {
                if !isZoomed {
                    Text("Pinch to zoom · swipe down to close")
                        .font(.caption2).foregroundStyle(.white.opacity(0.45))
                        .padding(.bottom, 18).allowsHitTesting(false)
                }
            }
        }
        .statusBarHidden(true)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !isZoomed, abs(value.translation.height) > abs(value.translation.width) else { return }
                dragDismiss = value.translation.height
            }
            .onEnded { value in
                guard !isZoomed else { dragDismiss = 0; return }
                if abs(dragDismiss) > 110 || (abs(dragDismiss) > 16 && abs(value.predictedEndTranslation.height) > 280) {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0)) { dragDismiss = 0 }
                }
            }
    }
}
