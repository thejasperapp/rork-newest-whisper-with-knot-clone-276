import SwiftUI

/// Global, user-visible error sink. Any layer can call
/// `WhisperErrorService.shared.report(...)` to surface a transient toast
/// banner at the top of the Whisper shell. The banner auto-dismisses after
/// a few seconds, can be tapped to dismiss, and de-duplicates rapid repeats
/// of the same message so flaky networks don't spam the user.
@MainActor
@Observable
final class WhisperErrorService {
    static let shared = WhisperErrorService()

    enum Severity: Sendable {
        case error
        case warning
        case info
    }

    struct Banner: Identifiable, Equatable, Sendable {
        let id: UUID
        let message: String
        let severity: Severity

        static func == (lhs: Banner, rhs: Banner) -> Bool {
            lhs.id == rhs.id
        }
    }

    private(set) var current: Banner?
    private var lastMessage: String?
    private var lastShownAt: Date = .distantPast
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func report(_ message: String, severity: Severity = .error) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Dedup: same message within 2.5s is dropped.
        if let last = lastMessage, last == trimmed,
           Date().timeIntervalSince(lastShownAt) < 2.5 {
            return
        }
        lastMessage = trimmed
        lastShownAt = Date()
        let banner = Banner(id: UUID(), message: trimmed, severity: severity)
        current = banner
        switch severity {
        case .error: WhisperFeedback.failed()
        case .warning: Haptics.warning()
        case .info: Haptics.soft()
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(severity == .info ? 2.4 : 4.0))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                if self?.current?.id == banner.id { self?.current = nil }
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

// MARK: - Banner view + modifier

private struct WhisperErrorBannerView: View {
    let banner: WhisperErrorService.Banner
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var icon: String {
        switch banner.severity {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch banner.severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return WhisperTheme.ink(scheme)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(banner.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WhisperTheme.ink(scheme))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(scheme))
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct WhisperGlobalErrorBanner: ViewModifier {
    @State private var service = WhisperErrorService.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let banner = service.current {
                    WhisperErrorBannerView(banner: banner) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            service.dismiss()
                        }
                    }
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: banner.id)
                    .zIndex(9999)
                }
            }
    }
}

extension View {
    /// Attach the global Whisper error toast. Place once at the root.
    func whisperGlobalErrorBanner() -> some View {
        modifier(WhisperGlobalErrorBanner())
    }
}
