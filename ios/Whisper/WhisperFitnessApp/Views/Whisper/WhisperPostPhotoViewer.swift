import SwiftUI

/// Fullscreen media paging. The horizontal scroll view owns unzoomed swipes;
/// each image owns its zoomed pan, and vertical dismissal only observes drags.
struct WhisperPostPhotoViewer: View {
    let urls: [URL]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageID: Int?
    @State private var isZoomed: Bool = false
    @State private var dragDismiss: CGFloat = 0
    @State private var verticalDrag: Bool?

    init(urls: [URL], startIndex: Int) {
        self.urls = urls
        self.startIndex = startIndex
        _pageID = State(initialValue: WhisperPhotoPagingPolicy.index(startIndex, count: urls.count))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if urls.isEmpty {
                    ContentUnavailableView("No photos available", systemImage: "photo")
                        .foregroundStyle(.white)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                                WhisperPostPhotoPage(url: url, isActive: pageID == index, onZoomChanged: { zoomed in
                                    if pageID == index {
                                        isZoomed = zoomed
                                        if zoomed { dragDismiss = 0; verticalDrag = nil }
                                    }
                                }, onDismiss: { dismiss() })
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $pageID)
                    .scrollDisabled(isZoomed)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .offset(y: dragDismiss)
                    .simultaneousGesture(dismissGesture)
                }
            }
            .overlay(alignment: .top) { header }
            .overlay(alignment: .bottom) { pageControl }
            .onChange(of: pageID) { _, _ in isZoomed = false; dragDismiss = 0; verticalDrag = nil }
            .task(id: pageID) {
                guard let pageID else { return }
                for index in [pageID - 1, pageID + 1] where urls.indices.contains(index) {
                    guard !Task.isCancelled else { return }
                    if !WhisperVideo.isVideo(urls[index]) { await WhisperImageCache.prefetch(urls[index]) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    private var header: some View {
        HStack {
            if urls.count > 1 {
                Text("\((pageID ?? 0) + 1) / \(urls.count)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Photo \((pageID ?? 0) + 1) of \(urls.count)")
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .accessibilityLabel("Close photo viewer")
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    @ViewBuilder private var pageControl: some View {
        if urls.count > 1 && urls.count <= 7 {
            HStack(spacing: 0) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, _ in
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { pageID = index }
                    } label: {
                        Circle().fill(.white.opacity(pageID == index ? 1 : 0.35))
                            .frame(width: 6, height: 6).frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Show photo \(index + 1)")
                    .accessibilityAddTraits(pageID == index ? .isSelected : [])
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !isZoomed else { return }
                if verticalDrag == nil {
                    verticalDrag = WhisperPhotoPagingPolicy.isVertical(value.translation)
                }
                if verticalDrag == true { dragDismiss = value.translation.height }
            }
            .onEnded { value in
                defer { verticalDrag = nil }
                if !isZoomed, verticalDrag == true,
                   abs(dragDismiss) > 120 || abs(value.predictedEndTranslation.height) > 260 {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0)) { dragDismiss = 0 }
                }
            }
    }
}
