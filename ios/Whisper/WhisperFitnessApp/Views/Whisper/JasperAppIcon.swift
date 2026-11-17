import SwiftUI

/// THE Jasper icon — the peach squircle with the dark ghost, bundled in the
/// asset catalog (`JasperIcon`). This is the one mark used ANYWHERE Jasper
/// needs an icon on iOS: the connect celebration, settings rows, the
/// onboarding link slide, Jasper's DM avatar, the Intelligence header, the
/// slash palette. Web renders the identical PNG (`/jasper-icon-v2.png`).
///
/// The artwork already carries its own squircle + soft edge, so the view only
/// scales it — no extra clip, no runtime fetch, never a flash of fallback.
struct JasperAppIcon: View {
    var size: CGFloat = 32
    /// Kept for call-site compatibility — the baked art defines its own
    /// corners, so this only tightens the outer clip for tiny sizes.
    var cornerScale: CGFloat = 0.24

    var body: some View {
        Image("JasperIcon")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * cornerScale, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The peach the icon is painted on — for glows and tints around it.
enum JasperIconPalette {
    static let peach: Color = Color(red: 0.855, green: 0.616, blue: 0.439)   // #DA9D70
    static let peachLight: Color = Color(red: 0.890, green: 0.710, blue: 0.553) // #E3B58D
    static let ink: Color = Color(red: 0.13, green: 0.09, blue: 0.07)
}
