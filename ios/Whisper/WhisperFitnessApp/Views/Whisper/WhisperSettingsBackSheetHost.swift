import SwiftUI

/// Hosts `WhisperSettingsView` behind the profile card. It is `Equatable`
/// and always equal, so SwiftUI does NOT re-evaluate the (very large)
/// settings body on every frame of the reveal drag — before this, every
/// pixel the card moved re-ran the whole menu's body, which is what made the
/// swipe feel like the app had locked up. `@State` writes made through the
/// captured closures still land (State storage is shared across copies).
struct WhisperSettingsBackSheetHost: View, Equatable {
    let onOpenSaved: () -> Void
    let onClose: () -> Void
    var onRootChanged: (Bool) -> Void = { _ in }

    static func == (lhs: WhisperSettingsBackSheetHost, rhs: WhisperSettingsBackSheetHost) -> Bool {
        true
    }

    var body: some View {
        WhisperSettingsView(onOpenSaved: onOpenSaved, onClose: onClose, onRootChanged: onRootChanged)
    }
}
