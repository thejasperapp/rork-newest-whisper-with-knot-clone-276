import SwiftUI

/// The one rounded box every editing tool lives in — a fixed height so the
/// canvas never jumps when the dial turns, a continuous 28 pt corner, a
/// hairline edge and a near-black surface, in the manner of the Photos
/// editor's control tray.
struct WhisperWaveToolPanel<Content: View>: View {
    var height: CGFloat = 216
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(12)
            .frame(height: height)
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .background(Color(white: 0.11), in: .rect(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal, 12)
    }
}

/// A round 40 pt icon button for panel headers — reset, remove, toggles.
struct WhisperWavePanelIconButton: View {
    let systemImage: String
    let label: String
    var isOn: Bool = false
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role) {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : (role == .destructive ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color.white))
                .frame(width: 40, height: 40)
                .background(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)), in: Circle())
        }
        .buttonStyle(WhisperMenuPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// A capsule chip for panel headers and preset rows — white when selected.
struct WhisperWavePanelChip: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
                }
                Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(selected ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
        }
        .buttonStyle(WhisperMenuPressStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A 56 × 64 preview tile with a caption — looks and effects both use it.
struct WhisperWavePreviewTile: View {
    let title: String
    let image: UIImage?
    let selected: Bool
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 4) {
                Color.white.opacity(0.08)
                    .frame(width: 56, height: 64)
                    .overlay {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
                        } else if let systemImage {
                            Image(systemName: systemImage).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? WhisperBrandGradient.accent : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1)
                    }
                Text(title)
                    .font(.system(size: 10, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
