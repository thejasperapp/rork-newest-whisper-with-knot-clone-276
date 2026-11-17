import SwiftUI

/// Monochrome PIN pad used for both creating and verifying the Whisper
/// quick-login PIN. Create mode asks twice (enter + confirm); verify mode
/// checks against the stored hash and shakes on a miss.
struct WhisperPinSheet: View {
    enum Mode {
        case create
        case verify
    }

    let mode: Mode
    /// Called with the confirmed PIN (create) or after a correct entry (verify).
    let onSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var entry: String = ""
    @State private var firstPass: String? = nil
    @State private var shake: Bool = false
    @State private var failures: Int = 0

    private let length: Int = 4

    var body: some View {
        VStack(spacing: 28) {
            Capsule()
                .fill(WhisperTheme.hairline(colorScheme))
                .frame(width: 40, height: 4)
                .padding(.top, 10)

            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            dots
                .offset(x: shake ? -10 : 0)
                .animation(shake ? .spring(response: 0.12, dampingFraction: 0.2) : .default, value: shake)

            keypad

            Button("Cancel") {
                Haptics.tap()
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.hidden)
    }

    private var title: String {
        switch mode {
        case .create: return firstPass == nil ? "Set your PIN" : "Confirm your PIN"
        case .verify: return "Enter your PIN"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create:
            return firstPass == nil
                ? "This PIN protects one-tap login on this device."
                : "Enter the same \(length) digits again."
        case .verify:
            return failures > 0 ? "That PIN didn't match. Try again." : "Unlock your saved login."
        }
    }

    private var dots: some View {
        HStack(spacing: 16) {
            ForEach(0..<length, id: \.self) { i in
                Circle()
                    .strokeBorder(WhisperTheme.ink(colorScheme), lineWidth: 1.5)
                    .background(
                        Circle().fill(i < entry.count ? WhisperTheme.ink(colorScheme) : .clear)
                    )
                    .frame(width: 16, height: 16)
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(1...3, id: \.self) { col in
                        key("\(row * 3 + col)")
                    }
                }
            }
            HStack(spacing: 22) {
                Color.clear.frame(width: 76, height: 62)
                key("0")
                Button {
                    Haptics.tap()
                    if !entry.isEmpty { entry.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 76, height: 62)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func key(_ digit: String) -> some View {
        Button {
            Haptics.tap()
            tap(digit)
        } label: {
            Text(digit)
                .font(.title2.weight(.medium))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 76, height: 62)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func tap(_ digit: String) {
        guard entry.count < length else { return }
        entry.append(digit)
        guard entry.count == length else { return }

        switch mode {
        case .create:
            if let first = firstPass {
                if first == entry {
                    Haptics.success()
                    onSuccess(entry)
                    dismiss()
                } else {
                    miss()
                    firstPass = nil
                }
            } else {
                firstPass = entry
                entry = ""
            }
        case .verify:
            if WhisperQuickLoginStore.shared.verifyPIN(entry) {
                Haptics.success()
                onSuccess(entry)
                dismiss()
            } else {
                miss()
            }
        }
    }

    private func miss() {
        Haptics.warning()
        failures += 1
        entry = ""
        shake = true
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            shake = false
        }
    }
}
