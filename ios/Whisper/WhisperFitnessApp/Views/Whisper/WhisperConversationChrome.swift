import SwiftUI

/// Native glass belongs to controls, never to the message content itself.
struct WhisperControlGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: shape)
                .overlay { shape.stroke(.primary.opacity(contrast == .increased ? 0.5 : 0.16), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay { shape.stroke(.primary.opacity(contrast == .increased ? 0.5 : 0.1), lineWidth: 0.5) }
        }
    }
}

enum WhisperConversationPortraitSize {
    static let header: CGFloat = 64
    static let inbox: CGFloat = 64
    static let message: CGFloat = 36
    static let details: CGFloat = 128
}

struct WhisperConversationHeader<Portrait: View, Actions: View>: View {
    let name: String
    var activity: String? = nil
    var activityAccessibilityLabel: String? = nil
    var showsNameWithActivity = false
    let onBack: () -> Void
    let onDetails: () -> Void
    @ViewBuilder let portrait: () -> Portrait
    @ViewBuilder let actions: () -> Actions

    @ViewBuilder var body: some View {
        if showsNameWithActivity {
            readableActivityHeader
        } else {
            standardHeader
        }
    }

    // A compact name pill overlaps the portrait. Active status can grow below
    // it without competing with the floating side controls.
    private var readableActivityHeader: some View {
        VStack(spacing: -7) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .modifier(WhisperControlGlass(shape: Circle()))
                }.buttonStyle(.plain).accessibilityLabel("Back")
                Spacer(minLength: 0)
                Button(action: onDetails) {
                    portrait().frame(width: WhisperConversationPortraitSize.header, height: WhisperConversationPortraitSize.header)
                }.buttonStyle(WhisperPortraitPressStyle())
                    .accessibilityLabel("\(name), conversation details")
                Spacer(minLength: 0)
                actions().frame(width: 44)
            }
            .zIndex(1)
            Button(action: onDetails) {
                VStack(spacing: 3) {
                    Text(name).font(.subheadline.weight(.semibold))
                    if let activity, !activity.isEmpty {
                        Text(activity)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, activity?.isEmpty == false ? 10 : 7)
                .frame(minHeight: 32)
                .modifier(WhisperControlGlass(shape: Capsule()))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 320)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.map { "\(name), \(activityAccessibilityLabel ?? $0), conversation details" } ?? "\(name), conversation details")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        .background { Color.clear.contentShape(.rect).onTapGesture { } }
    }

    private var standardHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .modifier(WhisperControlGlass(shape: Circle()))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            VStack(spacing: -1) {
                Button(action: onDetails) { portrait().frame(width: WhisperConversationPortraitSize.header, height: WhisperConversationPortraitSize.header) }
                    .buttonStyle(WhisperPortraitPressStyle()).accessibilityLabel("\(name), conversation details")
                    .zIndex(1)
                Button(action: onDetails) {
                    Text(activity ?? name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    .accessibilityLabel(activity.map { "\(name), \($0)" } ?? name)
                    .padding(.horizontal, 14).frame(minHeight: 32)
                    .modifier(WhisperControlGlass(shape: Capsule()))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(activity.map { "\(name), \(activityAccessibilityLabel ?? $0), conversation details" } ?? "\(name), conversation details")
            }
            .frame(maxWidth: .infinity)
            actions()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        .background {
            // The fading material is deliberately non-interactive, but the
            // header's gaps must not activate message avatars underneath it.
            Color.clear.contentShape(.rect).onTapGesture { }
        }
    }
}

/// Keep the scroll view behind floating controls with a quiet canvas fade.
/// Accessibility uses an opaque backing instead of simulated transparency.
struct WhisperConversationHeaderBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if reduceTransparency {
                WhisperChatAppearance.classic.palette(scheme).canvas
            } else {
                LinearGradient(stops: [
                    .init(color: WhisperChatAppearance.classic.palette(scheme).canvas.opacity(0.85), location: 0),
                    .init(color: WhisperChatAppearance.classic.palette(scheme).canvas.opacity(0.35), location: 0.4),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

struct WhisperConversationCallMenu: View {
    let audio: () -> Void
    var video: (() -> Void)? = nil

    var body: some View {
        Menu {
            Button("Audio call", systemImage: "phone", action: audio)
            if let video { Button("Video call", systemImage: "video", action: video) }
        } label: {
            Image(systemName: "phone")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 44)
                .modifier(WhisperControlGlass(shape: Circle()))
        }
        .accessibilityLabel("Call options")
    }
}
