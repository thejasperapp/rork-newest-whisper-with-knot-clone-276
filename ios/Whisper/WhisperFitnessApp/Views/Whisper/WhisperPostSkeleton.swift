import SwiftUI

private struct WhisperSkeletonPhaseKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    fileprivate var whisperSkeletonPhase: CGFloat {
        get { self[WhisperSkeletonPhaseKey.self] }
        set { self[WhisperSkeletonPhaseKey.self] = newValue }
    }
}

/// One clock per visible row, rather than a separate clock for every bone.
private struct WhisperSkeletonAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.whisperMediaActive) private var mediaActive
    @State private var visible: Bool = false

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || scenePhase != .active || !mediaActive || !visible)) { context in
            let phase = reduceMotion ? 0 : CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6)
            content.environment(\.whisperSkeletonPhase, phase)
        }
        .onScrollVisibilityChange(threshold: 0.05) { visible = $0 }
    }
}

struct WhisperSkeletonBone: View {
    var cornerRadius: CGFloat = 8
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperSkeletonPhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(WhisperTheme.ink(colorScheme).opacity(0.07))
                .overlay(alignment: .leading) {
                    if !reduceMotion {
                        LinearGradient(colors: [.clear, WhisperTheme.ink(colorScheme).opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(60, width * 0.55))
                            .offset(x: -width * 0.6 + width * 1.7 * phase)
                    }
                }
                .clipShape(.rect(cornerRadius: cornerRadius))
        }
        .accessibilityHidden(true)
    }
}

struct WhisperSkeletonDot: View {
    let size: CGFloat
    var body: some View {
        WhisperSkeletonBone(cornerRadius: size / 2).frame(width: size, height: size)
    }
}

struct WhisperPostSkeletonCard: View {
    var showMedia: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                WhisperSkeletonDot(size: 38)
                VStack(alignment: .leading, spacing: 5) {
                    WhisperSkeletonBone(cornerRadius: 5).frame(width: 118, height: 10)
                    WhisperSkeletonBone(cornerRadius: 4).frame(width: 64, height: 8)
                }
                Spacer(minLength: 0)
            }
            WhisperSkeletonBone(cornerRadius: 5).frame(height: 10)
            WhisperSkeletonBone(cornerRadius: 5).frame(height: 10).padding(.trailing, 90)
            if showMedia {
                WhisperSkeletonBone(cornerRadius: 14)
                    .aspectRatio(4 / 3, contentMode: .fit).frame(maxWidth: .infinity)
            }
            HStack(spacing: 14) {
                WhisperSkeletonDot(size: 24)
                WhisperSkeletonDot(size: 24)
                WhisperSkeletonDot(size: 24)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .modifier(WhisperSkeletonAnimation())
    }
}

/// Geometry is available on the first frame; no staggered blank loading cards.
struct WhisperPostSkeletonList: View {
    var count: Int = 3
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<max(0, count), id: \.self) { index in
                WhisperPostSkeletonCard(showMedia: index != 1)
                if index < count - 1 { Divider() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading posts")
    }
}

/// Mirrors an incoming answer without fabricating message text or progress.
struct WhisperKnotAnswerSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WhisperSkeletonBone(cornerRadius: 5).frame(width: 90, height: 12)
            WhisperSkeletonBone(cornerRadius: 5).frame(height: 11)
            WhisperSkeletonBone(cornerRadius: 5).frame(height: 11).padding(.trailing, 28)
            WhisperSkeletonBone(cornerRadius: 5).frame(height: 11).padding(.trailing, 86)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .modifier(WhisperSkeletonAnimation())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Knot is preparing a response")
        .allowsHitTesting(false)
    }
}

/// A deterministic conversation silhouette, not fake message content.
struct WhisperMessageThreadSkeleton: View {
    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<6) { index in
                HStack(alignment: .bottom, spacing: 8) {
                    if index % 3 == 1 { Spacer(minLength: 60) }
                    else { WhisperSkeletonDot(size: 26) }
                    WhisperSkeletonBone(cornerRadius: 22)
                        .frame(width: index % 2 == 0 ? 204 : 158, height: index % 3 == 0 ? 68 : 42)
                    if index % 3 != 1 { Spacer(minLength: 16) }
                }
            }
        }
        .padding(.vertical, 20)
        .modifier(WhisperSkeletonAnimation())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading messages")
        .allowsHitTesting(false)
    }
}

struct WhisperCommentSkeletonRow: View {
    var index: Int = 0
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            WhisperSkeletonDot(size: 32)
            VStack(alignment: .leading, spacing: 6) {
                WhisperSkeletonBone(cornerRadius: 4).frame(width: 96, height: 8)
                WhisperSkeletonBone(cornerRadius: 5).frame(height: 10)
                WhisperSkeletonBone(cornerRadius: 5).frame(height: 10).padding(.trailing, 70)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .modifier(WhisperSkeletonAnimation())
        .accessibilityHidden(true)
    }
}
