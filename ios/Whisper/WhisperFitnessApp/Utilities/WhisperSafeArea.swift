import UIKit

/// Window safe-area insets for full-bleed surfaces that ignore the safe
/// area themselves (the Waves player, story chrome) but still need to sit
/// the same distance under the notch / Dynamic Island on every phone.
enum WhisperSafeArea {
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }

    /// Top inset (59 on Dynamic Island phones, 47 on notch phones, 20 on
    /// older devices). Falls back to 47 before the window exists.
    static var top: CGFloat {
        let v = keyWindow?.safeAreaInsets.top ?? 0
        return v > 0 ? v : 47
    }

    /// Bottom inset (34 on home-indicator phones, 0 otherwise).
    static var bottom: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 0
    }
}
