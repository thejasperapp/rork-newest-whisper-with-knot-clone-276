import SwiftUI
import UIKit

/// Beautiful share surface for a badge. Renders a 9:16 vertical card that
/// matches the celebration popup's aesthetic so users can drop it straight
/// onto Instagram stories, save it to Photos, or pass it to any system
/// share target.
struct WhisperBadgeShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let kind: WhisperBadgeKind

    @State private var renderedImage: UIImage?
    @State private var showSystemShare: Bool = false
    @State private var savedToast: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        kind.accent.opacity(0.28),
                        WhisperTheme.surface(colorScheme),
                        WhisperTheme.surface(colorScheme)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        Text("Share your badge")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.top, 6)
                        Text("Post it to your stories, send it to friends, or save it to Photos.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.horizontal, 28)

                        card
                            .frame(width: 270, height: 480)
                            .clipShape(.rect(cornerRadius: 28))
                            .shadow(color: kind.accent.opacity(0.35), radius: 24, x: 0, y: 10)
                            .padding(.top, 4)

                        actions
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 24)
                }

                if savedToast {
                    VStack {
                        Spacer()
                        Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.black.opacity(0.78), in: Capsule())
                            .padding(.bottom, 32)
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .onAppear { renderImage() }
        .sheet(isPresented: $showSystemShare) {
            if let renderedImage {
                ShareActivityView(items: [renderedImage])
            }
        }
    }

    // MARK: - Card

    /// The full 9:16 shareable card. Also used as the source for the
    /// rendered UIImage.
    private var card: some View {
        WhisperBadgeShareCard(kind: kind)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                if renderedImage == nil { renderImage() }
                showSystemShare = true
            } label: {
                actionLabel(icon: "square.and.arrow.up", text: "Share…", filled: true)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                saveToPhotos()
            } label: {
                actionLabel(icon: "square.and.arrow.down", text: "Save to Photos", filled: false)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                copyToPasteboard()
            } label: {
                actionLabel(icon: "doc.on.doc", text: "Copy image", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func actionLabel(icon: String, text: String, filled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
            Text(text)
                .font(.subheadline.weight(.bold))
        }
        .foregroundStyle(filled ? .white : WhisperTheme.ink(colorScheme))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            filled ? AnyShapeStyle(kind.accent) : AnyShapeStyle(WhisperTheme.card(colorScheme)),
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    filled ? .clear : WhisperTheme.hairline(colorScheme),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Rendering

    /// Snapshots `card` to a UIImage so we can hand it to UIActivityVC,
    /// `UIImageWriteToSavedPhotosAlbum`, or `UIPasteboard`.
    private func renderImage() {
        let renderer = ImageRenderer(
            content: WhisperBadgeShareCard(kind: kind)
                .frame(width: 1080, height: 1920)
        )
        renderer.scale = 1
        renderer.proposedSize = .init(width: 1080, height: 1920)
        renderedImage = renderer.uiImage
    }

    private func saveToPhotos() {
        if renderedImage == nil { renderImage() }
        guard let image = renderedImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        Haptics.success()
        withAnimation { savedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { savedToast = false }
        }
    }

    private func copyToPasteboard() {
        if renderedImage == nil { renderImage() }
        guard let image = renderedImage else { return }
        UIPasteboard.general.image = image
        Haptics.success()
    }
}

/// 9:16 shareable card design. Used both for the live in-sheet preview and
/// (via `ImageRenderer`) the exported UIImage.
struct WhisperBadgeShareCard: View {
    let kind: WhisperBadgeKind

    @State private var liar = WhisperLiarLiarService.shared

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 1080.0
            ZStack {
                // Accent gradient backdrop — each badge gets its own palette
                // pulled from `kind.accent` so the card feels bespoke per chip.
                LinearGradient(
                    colors: [
                        kind.accent,
                        kind.accent.opacity(0.85),
                        kind.accent.opacity(0.55),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Secondary radial wash for depth
                RadialGradient(
                    colors: [Color.white.opacity(0.35), .clear],
                    center: .topTrailing,
                    startRadius: 40 * scale,
                    endRadius: 900 * scale
                )
                .blendMode(.plusLighter)

                // Soft glow behind glyph
                Circle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 660 * scale, height: 660 * scale)
                    .blur(radius: 90 * scale)
                    .offset(y: -80 * scale)

                VStack(spacing: 0) {
                    Spacer(minLength: 90 * scale)

                    Text("WHISPER")
                        .font(.system(size: 44 * scale, weight: .black))
                        .tracking(8 * scale)
                        .foregroundStyle(.white.opacity(0.92))

                    Spacer(minLength: 30 * scale)

                    // Glyph
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 520 * scale, height: 520 * scale)
                        Circle()
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 4 * scale)
                            .frame(width: 520 * scale, height: 520 * scale)
                        kind.view(size: 280 * scale, liar: liar)
                            .shadow(color: .black.opacity(0.4), radius: 30 * scale, x: 0, y: 18 * scale)
                    }

                    Spacer(minLength: 36 * scale)

                    Text("BADGE UNLOCKED")
                        .font(.system(size: 26 * scale, weight: .bold))
                        .tracking(6 * scale)
                        .foregroundStyle(.white.opacity(0.85))

                    Text(kind.title)
                        .font(.system(size: 84 * scale, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 60 * scale)
                        .padding(.top, 10 * scale)

                    Text(kind.tagline)
                        .font(.system(size: 34 * scale, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 80 * scale)
                        .padding(.top, 14 * scale)

                    // Long-form description so non-recipients viewing the
                    // shared card understand what the badge means.
                    Text(kind.explainer)
                        .font(.system(size: 24 * scale, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 90 * scale)
                        .padding(.top, 22 * scale)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    // Footer — W logo bottom-left, slogan to the right.
                    HStack(alignment: .center, spacing: 14 * scale) {
                        Image("WhisperLogo")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .frame(width: 96 * scale, height: 96 * scale)
                        VStack(alignment: .leading, spacing: 2 * scale) {
                            Text("Whisper")
                                .font(.system(size: 30 * scale, weight: .black))
                                .foregroundStyle(.white)
                            Text("fitness made social")
                                .font(.system(size: 22 * scale, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 70 * scale)
                    .padding(.bottom, 80 * scale)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .aspectRatio(9.0/16.0, contentMode: .fit)
    }
}

/// Thin UIKit wrapper for `UIActivityViewController` so we can present
/// the system share sheet from SwiftUI.
struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
