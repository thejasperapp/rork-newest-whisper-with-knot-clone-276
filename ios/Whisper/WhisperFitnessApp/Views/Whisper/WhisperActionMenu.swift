import SwiftUI

// MARK: - Whisper branded action menu
//
// Shared branded bottom sheet for custom overflow actions. Native system
// menus retain their platform presentation. Usage:
//
//   @State private var actionMenu: WhisperActionMenuModel?
//   ...
//   Button { actionMenu = WhisperActionMenuModel(...) } label: { ... }
//   ...
//   .whisperActionMenu($actionMenu)

/// One tappable row inside the branded action sheet.
struct WhisperMenuAction: Identifiable {
    let id = UUID()
    var icon: String
    var title: String
    var subtitle: String? = nil
    var isDestructive: Bool = false
    /// Optional tint for the icon tile (defaults to ink, red when destructive).
    var tint: Color? = nil
    var handler: () -> Void
}

/// The full menu payload — drives `.whisperActionMenu(_:)`.
struct WhisperActionMenuModel: Identifiable {
    let id = UUID()
    /// Optional header title, e.g. "@username" or "Unsend message?".
    var title: String? = nil
    /// Optional header subtitle / explainer text.
    var subtitle: String? = nil
    /// Emoji reaction strip shown above the actions (DM long-press variant).
    var reactions: [String] = []
    /// Currently-selected reaction (renders with a filled ring).
    var selectedReaction: String? = nil
    var onReaction: ((String) -> Void)? = nil
    var actions: [WhisperMenuAction]
    /// Confirm style renders the (single) destructive action as a large
    /// filled red button — used for Block / Unsend / Log out confirmations.
    var isConfirmStyle: Bool = false

    /// Sheet height for the `.height` detent.
    var estimatedHeight: CGFloat {
        var h: CGFloat = 46 // grabber + top padding
        if title != nil { h += 30 }
        if subtitle != nil { h += 40 }
        if title != nil || subtitle != nil { h += 14 }
        if !reactions.isEmpty { h += 68 }
        if isConfirmStyle {
            h += CGFloat(actions.count) * 60
        } else {
            h += CGFloat(actions.count) * 56
        }
        h += 74 // cancel button + bottom padding
        return min(h, 640)
    }
}

/// The sheet content itself. Rows animate in with a quick stagger; every
/// tap fires a haptic, runs the handler, and dismisses.
struct WhisperActionMenuSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let model: WhisperActionMenuModel
    let dismiss: () -> Void

    @State private var appeared: Bool = false
    @State private var didSelect: Bool = false
    @State private var ownerGeneration: UUID = AccountStorage.generation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule()
                    .fill(WhisperTheme.muted(colorScheme).opacity(0.45))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                if model.title != nil || model.subtitle != nil {
                    VStack(spacing: 4) {
                        if let title = model.title {
                            Text(title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let subtitle = model.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 28)
                        }
                    }
                    .padding(.bottom, 14)
                }

                if !model.reactions.isEmpty {
                    reactionStrip
                        .padding(.bottom, 12)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        if model.isConfirmStyle {
                            confirmRows
                        } else {
                            listRows
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                cancelButton
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .whisperSmooth) { appeared = true }
        }
    }

    // MARK: Reactions (DM long-press)

    private var reactionStrip: some View {
        HStack(spacing: 10) {
            ForEach(Array(model.reactions.enumerated()), id: \.offset) { idx, emoji in
                Button {
                    guard !didSelect, ownerGeneration == AccountStorage.generation else { return }
                    didSelect = true
                    Haptics.success()
                    model.onReaction?(emoji)
                    dismiss()
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill(
                                model.selectedReaction == emoji
                                    ? WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.28 : 0.12)
                                    : WhisperTheme.card(colorScheme)
                            )
                        )
                        .overlay {
                            if model.selectedReaction == emoji {
                                Circle().strokeBorder(WhisperTheme.ink(colorScheme), lineWidth: 1.5)
                            }
                        }
                        .scaleEffect(appeared ? 1 : 0.4)
                        .opacity(appeared ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.68).delay(Double(idx) * 0.035),
                            value: appeared
                        )
                }
                .buttonStyle(WhisperMenuPressStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Standard rows

    private var listRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { idx, action in
                Button {
                    guard !didSelect, ownerGeneration == AccountStorage.generation else { return }
                    didSelect = true
                    if action.isDestructive { Haptics.warning() } else { Haptics.tap() }
                    dismiss()
                    // Run after the sheet starts dismissing so any follow-up
                    // presentation (report sheet, forward sheet…) doesn't
                    // race this sheet's teardown.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        guard ownerGeneration == AccountStorage.generation else { return }
                        action.handler()
                    }
                } label: {
                    HStack(spacing: 12) {
                        iconTile(action)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.title)
                                .font(.body.weight(action.isDestructive ? .semibold : .regular))
                                .foregroundStyle(action.isDestructive ? Color.red : WhisperTheme.ink(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                            if let sub = action.subtitle {
                                Text(sub)
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, action.subtitle == nil ? 12 : 9)
                    .contentShape(.rect)
                }
                .buttonStyle(WhisperMenuPressStyle())
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.85).delay(Double(idx) * 0.03),
                    value: appeared
                )
                if idx < model.actions.count - 1 {
                    Rectangle()
                        .fill(WhisperTheme.hairline(colorScheme))
                        .frame(height: 0.5)
                        .padding(.leading, 58)
                }
            }
        }
        .background(WhisperTheme.card(colorScheme))
        .clipShape(.rect(cornerRadius: WhisperMenuGeometry.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WhisperMenuGeometry.cardRadius, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: Confirm style (Block / Unsend / Log out)

    private var confirmRows: some View {
        VStack(spacing: 10) {
            ForEach(model.actions) { action in
                Button {
                    guard !didSelect, ownerGeneration == AccountStorage.generation else { return }
                    didSelect = true
                    if action.isDestructive { Haptics.warning() } else { Haptics.tap() }
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        guard ownerGeneration == AccountStorage.generation else { return }
                        action.handler()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: action.icon)
                            .font(.subheadline.weight(.bold))
                        Text(action.title)
                            .font(.body.weight(.bold))
                    }
                    .foregroundStyle(action.isDestructive ? Color.white : WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        action.isDestructive ? Color.red : WhisperTheme.ink(colorScheme),
                        in: .rect(cornerRadius: WhisperMenuGeometry.controlRadius, style: .continuous)
                    )
                }
                .buttonStyle(WhisperMenuPressStyle())
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(reduceMotion ? nil : .whisperSmooth, value: appeared)
    }

    private var cancelButton: some View {
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            Text("Cancel")
                .font(.body.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: WhisperMenuGeometry.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: WhisperMenuGeometry.controlRadius, style: .continuous)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
        .buttonStyle(WhisperMenuPressStyle())
    }

    private func iconTile(_ action: WhisperMenuAction) -> some View {
        let color = action.isDestructive ? Color.red : (action.tint ?? WhisperTheme.ink(colorScheme))
        return Image(systemName: action.icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(colorScheme == .dark ? 0.16 : 0.08), in: .rect(cornerRadius: 9))
    }
}

/// Press feedback shared by every menu row — quick scale-down + opacity,
/// the same micro-interaction language as the rest of Whisper.
struct WhisperMenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension View {
    /// Presents the branded Whisper action sheet when `model` is non-nil.
    /// Drop-in replacement for `confirmationDialog` / inline `Menu`.
    func whisperActionMenu(_ model: Binding<WhisperActionMenuModel?>) -> some View {
        sheet(item: model) { m in
            WhisperActionMenuSheet(model: m) { model.wrappedValue = nil }
                .presentationDetents([.height(m.estimatedHeight), .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(WhisperMenuGeometry.sheetRadius)
        }
    }
}
