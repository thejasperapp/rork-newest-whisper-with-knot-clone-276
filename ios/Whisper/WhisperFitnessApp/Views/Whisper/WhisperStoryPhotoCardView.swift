import SwiftUI

/// Shared creator/viewer geometry for captioned Frames and single-piece Photostrips.
struct WhisperStoryPhotoCardView: View {
    let sticker: WhisperStorySticker
    var stageWidth: CGFloat = 390
    var localImage: UIImage? = nil
    var isRevealed: Bool = true
    var onReveal: (() -> Void)? = nil
    var onMediaReady: (() -> Void)? = nil
    var caption: Binding<String>? = nil
    var captionFocus: FocusState<Bool>.Binding? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var retryID: UUID = UUID()

    private var isStrip: Bool { sticker.photoLayout == "strip" }
    private var monochrome: Bool { isStrip && sticker.style == 1 }
    private var ink: Color { monochrome ? .white : .black }
    private var width: CGFloat {
        let fraction = sticker.cardWidthFraction ?? (isStrip ? 0.26 : 0.58)
        return max(44, stageWidth * CGFloat(fraction.isFinite ? min(0.85, max(0.15, fraction)) : 0.58))
    }
    private var ratio: CGFloat {
        let value = sticker.mediaAspectRatio ?? 1
        return CGFloat(value.isFinite ? min(3, max(0.15, value)) : 1)
    }
    private var hidden: Bool { sticker.isRevealFrame && !isRevealed }
    private var timestamp: String? {
        guard let raw = sticker.frameTimestamp,
              let date = ISO8601DateFormatter().date(from: raw) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: isStrip ? .center : .leading, spacing: 0) {
            photo
                .saturation(monochrome ? 0 : 1)
                .overlay { if !isStrip { Rectangle().strokeBorder(.black.opacity(0.12), lineWidth: 1) } }
            footer.padding(.top, isStrip ? 7 : 10).padding(.bottom, isStrip ? 5 : 6)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(isStrip ? 6 : 10)
        .frame(width: width)
        .background {
            if isStrip && sticker.style == 2 {
                LinearGradient(colors: [Color(red: 0.82, green: 0.98, blue: 0.96), .white, Color(red: 0.98, green: 0.83, blue: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else { monochrome ? Color.black : Color.white }
        }
        .clipShape(.rect(cornerRadius: 2))
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }

    private var photo: some View {
        (isStrip ? Color.clear : Color(white: 0.88))
            .frame(width: width - (isStrip ? 12 : 20), height: (width - (isStrip ? 12 : 20)) / ratio)
            .overlay {
                if let localImage {
                    Image(uiImage: localImage).resizable().scaledToFill().allowsHitTesting(false)
                } else if let raw = sticker.imageURL, let url = URL(string: raw) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill().allowsHitTesting(false)
                                .onAppear { onMediaReady?() }
                        case .failure:
                            if onReveal != nil {
                                Button { retryID = UUID() } label: {
                                    Label("Retry photo", systemImage: "arrow.clockwise").font(.caption).frame(minWidth: 44, minHeight: 44)
                                }.foregroundStyle(ink)
                            } else { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.gray) }
                        default: ProgressView().tint(.gray)
                        }
                    }.id(retryID)
                }
            }
            .clipped()
            .overlay {
                if hidden {
                    Button { onReveal?() } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "iphone.radiowaves.left.and.right").font(.title2)
                            Text("Shake or tap\nto reveal").font(.caption.weight(.medium)).multilineTextAlignment(.center)
                        }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(white: 0.2))
                    }.buttonStyle(.plain).accessibilityLabel("Reveal framed photo")
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: hidden)
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: isStrip ? .center : .leading, spacing: 4) {
            if let caption {
                TextField("Add a caption…", text: caption, axis: .vertical)
                    .font(isStrip ? .caption : .subheadline).foregroundStyle(ink)
                    .tint(monochrome ? .white : .black).lineLimit(1...4)
                    .multilineTextAlignment(isStrip ? .center : .leading)
                    .focused(captionFocus ?? $unusedFocus)
                    .environment(\.colorScheme, monochrome ? .dark : .light)
            } else if let text = sticker.text, !text.isEmpty {
                Text(text).font(isStrip ? .caption : .subheadline).foregroundStyle(ink)
                    .multilineTextAlignment(isStrip ? .center : .leading).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel(text)
            }
            if !isStrip, let timestamp {
                Text(timestamp).font(.system(size: 10)).foregroundStyle(.black.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: isStrip ? .center : .leading)
    }
    @FocusState private var unusedFocus: Bool
}
