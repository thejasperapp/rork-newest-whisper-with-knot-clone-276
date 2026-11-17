import SwiftUI

/// Instagram-style crop-before-upload for profile photos — the web cropper's
/// iOS twin. Drag to reposition, pinch or use the slider to zoom, a circular
/// mask previews the final avatar; Save bakes a clean square crop and hands
/// back JPEG bytes ready to upload.
struct WhisperAvatarCropperSheet: View {
    let image: UIImage
    let onCrop: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    /// Diameter of the circular crop stage on screen.
    @State private var stage: CGFloat = 240
    @State private var saveFailed = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    stageView
                    Text("Drag to reposition · pinch to zoom")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 12) {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 1...4, onEditingChanged: { editing in
                            if !editing {
                                steadyZoom = zoom
                                clampOffset()
                            }
                        })
                        .tint(.white)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 26)
                    if saveFailed {
                        Text("Couldn't prepare this crop. Try again.")
                            .font(.caption).foregroundStyle(.white)
                    }
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(120, min(300, proxy.size.width - 40, proxy.size.height - 140))
            } action: { newStage in
                let ratio = newStage / max(stage, 1)
                offset = CGSize(width: offset.width * ratio, height: offset.height * ratio)
                steadyOffset = CGSize(width: steadyOffset.width * ratio, height: steadyOffset.height * ratio)
                stage = newStage
                clampOffset()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button("Cancel") {
                    Haptics.tap()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 60, minHeight: 44)
                Spacer()
                Text("Crop")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Save") {
                    clampOffset()
                    guard let data = bake() else { saveFailed = true; return }
                    Haptics.success()
                    onCrop(data)
                    dismiss()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(minWidth: 60, minHeight: 44)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .background(Color.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var stageView: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: stage, height: stage)
                .scaleEffect(zoom)
                .offset(offset)
        }
        .frame(width: stage, height: stage)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2)
        }
        .contentShape(Circle())
        .gesture(dragGesture.simultaneously(with: magnifyGesture))
        .accessibilityLabel("Crop stage — drag to reposition, pinch to zoom")
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                clampOffset()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(steadyZoom * value.magnification, 1), 4)
            }
            .onEnded { _ in
                steadyZoom = zoom
                clampOffset()
            }
    }

    /// The image is drawn aspect-fill inside the stage then scaled by `zoom`;
    /// clamp the pan so the circle can never show empty space.
    private func clampOffset() {
        let fillScale = stage / max(min(image.size.width, image.size.height), 1)
        let dispW = image.size.width * fillScale * zoom
        let dispH = image.size.height * fillScale * zoom
        let maxX = max((dispW - stage) / 2, 0)
        let maxY = max((dispH - stage) / 2, 0)
        let clamped = CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset = clamped
        }
        steadyOffset = clamped
    }

    /// Renders the visible circle region into a 640×640 square JPEG.
    private func bake() -> Data? {
        let side: CGFloat = 640
        let k = side / stage
        let fillScale = stage / max(min(image.size.width, image.size.height), 1)
        let s = fillScale * zoom
        let dispW = image.size.width * s
        let dispH = image.size.height * s
        let originX = (stage / 2 + offset.width - dispW / 2) * k
        let originY = (stage / 2 + offset.height - dispH / 2) * k
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let out = renderer.image { _ in
            image.draw(in: CGRect(x: originX, y: originY, width: dispW * k, height: dispH * k))
        }
        return out.jpegData(compressionQuality: 0.88)
    }
}
