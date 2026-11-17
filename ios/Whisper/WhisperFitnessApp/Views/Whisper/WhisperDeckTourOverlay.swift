import SwiftUI
import UIKit

/// Full-screen synced walkthrough overlay — the iOS twin of the web's
/// `EmberDeckTourOverlay`. The reading highlight follows Jasper's narration,
/// stat chips echo the deck, and the interactive slides embed the REAL
/// native pitch components (WPP slider calculator, brand marketplace cards)
/// so nobody leaves the meeting.
struct WhisperDeckTourOverlay: View {
    let tour: WhisperDeckTourViewState
    let isDriver: Bool
    let narration: WhisperDeckTourEngine.NarrationPhase
    /// Real window safe-area insets — the call stage ignores the container
    /// safe area, so the card positions itself inside the visible screen.
    var safeInsets: UIEdgeInsets = .zero
    var onClose: () -> Void
    var onPrev: () -> Void
    var onNext: () -> Void
    var onTogglePlay: () -> Void

    private static let accent = Color(red: 0.98, green: 0.57, blue: 0.24)
    private static let accentSoft = Color(red: 0.99, green: 0.73, blue: 0.45)

    private var position: (slide: Int, segment: Int) {
        WhisperDeckTourScript.clamp(slide: tour.slide, segment: tour.segment)
    }
    private var slide: WhisperDeckTourSlide {
        WhisperDeckTourScript.slides[position.slide]
    }

    private var statusLine: String {
        if isDriver {
            if !tour.playing { return "Paused — the room stays on this line" }
            switch narration {
            case .connecting: return "Warming up Jasper's voice…"
            case .live: return "Live — every device hears Jasper"
            case .off: return "Voice unavailable — advancing silently"
            }
        }
        return tour.deviceVoice
            ? "@\(tour.driverName) is presenting — Jasper narrates on this device"
            : "@\(tour.driverName) is presenting — Jasper reads over their audio"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { } // swallow taps so the call behind stays put

            VStack(spacing: 0) {
                header
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                slideBody
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                footer
            }
            .background(Color(red: 0.045, green: 0.045, blue: 0.055), in: .rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            // Fill the visible screen with slim margins — the meeting stage
            // ignores the container safe area, so the card pads itself off
            // the REAL window insets (status bar + home indicator) and a
            // sane width cap keeps iPad readable.
            .frame(maxWidth: 560, maxHeight: .infinity)
            .padding(.horizontal, 6)
            .padding(.top, max(safeInsets.top, 8) + 2)
            .padding(.bottom, max(safeInsets.bottom, 8) + 2)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Self.accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                if isDriver && narration == .connecting && tour.playing {
                    ProgressView()
                        .tint(Self.accent)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Self.accent)
                        .symbolEffect(.pulse, isActive: tour.playing)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Jasper deck walkthrough")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(statusLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                ForEach(Array(WhisperDeckTourScript.slides.enumerated()), id: \.element.id) { index, _ in
                    Capsule()
                        .fill(index == position.slide ? Self.accent : Color.white.opacity(0.2))
                        .frame(width: index == position.slide ? 16 : 5, height: 5)
                        .animation(.spring(duration: 0.3), value: position.slide)
                }
            }
            Button {
                Haptics.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDriver ? "End walkthrough" : "Hide walkthrough")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Body

    private var slideBody: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(slide.kicker.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.4)
                            .foregroundStyle(Self.accent)
                        Text(slide.title)
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 8) {
                        ForEach(Array(slide.segments.enumerated()), id: \.element.id) { index, segment in
                            segmentRow(segment, index: index)
                                .id(segment.id)
                        }
                    }

                    if !slide.stats.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(slide.stats, id: \.label) { stat in
                                VStack(spacing: 3) {
                                    Text(stat.value)
                                        .font(.system(size: 17, weight: .black))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(stat.label.uppercased())
                                        .font(.system(size: 7.5, weight: .bold))
                                        .tracking(0.4)
                                        .foregroundStyle(.white.opacity(0.45))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 6)
                                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
                            }
                        }
                    }

                    if let interactive = slide.interactive {
                        if let hint = slide.interactiveHint {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                Text(hint)
                                    .font(.system(size: 11.5, weight: .bold))
                            }
                            .foregroundStyle(Self.accentSoft)
                        }
                        switch interactive {
                        case .wpp:
                            WhisperWppCalculatorCard()
                        case .brands:
                            WhisperTourBrandCards()
                        }
                    }
                }
                .padding(14)
            }
            .onChange(of: position.segment) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(slide.segments[position.segment].id, anchor: .center)
                }
            }
            .onChange(of: position.slide) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(slide.segments[0].id, anchor: .top)
                }
            }
        }
    }

    private func segmentRow(_ segment: WhisperDeckTourSegment, index: Int) -> some View {
        let isActive = index == position.segment
        let isRead = index < position.segment
        return HStack(alignment: .top, spacing: 10) {
            Group {
                if isRead {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Self.accentSoft.opacity(0.8))
                } else if isActive {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Self.accent)
                        .symbolEffect(.pulse, isActive: tour.playing)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 5, height: 5)
                        .padding(.top, 4)
                }
            }
            .frame(width: 14)
            .padding(.top, 2)

            Text(segment.text)
                .font(.system(size: 13.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(isRead ? 0.6 : 0.55))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            isActive ? Self.accent.opacity(0.12) : Color.white.opacity(isRead ? 0.04 : 0),
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isActive ? Self.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        }
        .opacity(isActive || isRead ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.25), value: position.segment)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if isDriver {
            HStack(spacing: 8) {
                footerCircleButton("chevron.left", disabled: position.slide == 0) {
                    onPrev()
                }
                Button {
                    Haptics.tap()
                    onTogglePlay()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tour.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(tour.playing ? "Pause" : "Resume")
                            .font(.system(size: 12.5, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Self.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                footerCircleButton("chevron.right", disabled: position.slide == WhisperDeckTourScript.slides.count - 1) {
                    onNext()
                }
                Spacer(minLength: 4)
                Text("\(position.slide + 1) / \(WhisperDeckTourScript.slides.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Button {
                    Haptics.tap()
                    onClose()
                } label: {
                    Text("End")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Color.red.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End walkthrough for everyone")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Self.accentSoft)
                    Text(tour.deviceVoice
                         ? "Jasper's narration plays right on this device"
                         : "Jasper's voice plays through @\(tour.driverName)'s audio")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(position.slide + 1) / \(WhisperDeckTourScript.slides.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Button {
                    Haptics.tap()
                    onClose()
                } label: {
                    Text("Hide")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func footerCircleButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

// MARK: - WPP calculator (native twin of the web pitch component)

/// The real WPP earnings math from the pitch deck — same tiers as the web
/// (`WPP_TIERS`): Partner $0.90/1k at 1k+ followers, Partner+ $1.40/1k at
/// 10k+, Elite $2.20/1k at 100k+.
struct WhisperWppCalculatorCard: View {
    @State private var followers: Double = 25_000
    @State private var monthlyViews: Double = 250_000

    private static let accent = Color(red: 0.98, green: 0.57, blue: 0.24)

    private struct Tier {
        let name: String
        let rpmCents: Int
        let minFollowers: Int
    }

    private static let tiers: [Tier] = [
        Tier(name: "Partner", rpmCents: 90, minFollowers: 1_000),
        Tier(name: "Partner+", rpmCents: 140, minFollowers: 10_000),
        Tier(name: "Elite", rpmCents: 220, minFollowers: 100_000),
    ]

    private var tier: Tier {
        if followers >= 100_000 { return Self.tiers[2] }
        if followers >= 10_000 { return Self.tiers[1] }
        return Self.tiers[0]
    }

    private var payoutCents: Int {
        Int((monthlyViews / 1_000) * Double(tier.rpmCents))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Self.accent)
                Text("WPP EARNINGS CALCULATOR")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("LIVE MATH")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(Self.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Self.accent.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 5) {
                ForEach(Self.tiers, id: \.name) { item in
                    VStack(spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(tier.name == item.name ? .black : .white.opacity(0.6))
                        Text("\(Self.usd(item.rpmCents))/1k")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tier.name == item.name ? .black.opacity(0.7) : .white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        tier.name == item.name ? AnyShapeStyle(Self.accent) : AnyShapeStyle(Color.white.opacity(0.07)),
                        in: .rect(cornerRadius: 10)
                    )
                    .animation(.spring(duration: 0.25), value: tier.name)
                }
            }

            sliderRow(
                label: "Followers",
                display: Self.compact(followers),
                value: $followers,
                range: 1_000...250_000,
                step: 1_000
            )
            sliderRow(
                label: "Monthly views",
                display: Self.compact(monthlyViews),
                value: $monthlyViews,
                range: 10_000...2_000_000,
                step: 10_000
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Self.usd(payoutCents))
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.3), value: payoutCents)
                    Text("/mo")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text("Estimated at \(Self.usd(tier.rpmCents)) per 1k qualified views on the \(tier.name) tier — paid monthly via Stripe.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Self.accent.opacity(0.22), lineWidth: 1)
        }
    }

    private func sliderRow(
        label: String,
        display: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 8.5, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text(display)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Slider(value: value, in: range, step: step)
                .tint(Self.accent)
        }
    }

    private static func usd(_ cents: Int) -> String {
        if cents % 100 == 0 {
            let dollars = cents / 100
            return "$\(dollars.formatted(.number.grouping(.automatic)))"
        }
        return String(format: "$%.2f", Double(cents) / 100)
    }

    private static func compact(_ value: Double) -> String {
        if value >= 1_000_000 {
            let millions = value / 1_000_000
            return millions == millions.rounded() ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        }
        if value >= 1_000 { return "\(Int(value / 1_000))k" }
        return "\(Int(value))"
    }
}

// MARK: - Brand marketplace cards (native twin of the web pitch component)

nonisolated private struct WhisperTourBrand: Identifiable {
    let id: String
    let name: String
    let handle: String
    let industry: String
    let payText: String
    let basisText: String
    let minFollowers: String
    let about: String
    let perks: [String]
    let terms: String
    let score: Int
}

/// The three sample brands from the pitch deck, with the same requirements,
/// typical pay, and escrow terms the web modals show.
struct WhisperTourBrandCards: View {
    @State private var expandedID: String?
    @State private var appliedIDs: Set<String> = []

    private static let accent = Color(red: 0.98, green: 0.57, blue: 0.24)

    private static let brands: [WhisperTourBrand] = [
        WhisperTourBrand(
            id: "sample-apex",
            name: "Apex Nutrition",
            handle: "apexnutrition",
            industry: "Supplements",
            payText: "$150–$600",
            basisText: "per post",
            minFollowers: "2,500+ followers",
            about: "Performance supplements for lifters and endurance athletes. We sponsor creators who post honest training content — no script, no fake hype.",
            perks: ["Free monthly product box", "Discount code for your audience", "Early product drops"],
            terms: "Escrowed on acceptance, released when the tracked post goes live.",
            score: 94
        ),
        WhisperTourBrand(
            id: "sample-stride",
            name: "Stride Athletics",
            handle: "strideathletics",
            industry: "Apparel",
            payText: "$400–$1,200",
            basisText: "per month",
            minFollowers: "5,000+ followers",
            about: "Training apparel built for athletes. Monthly ambassador deals for athletes who compete and post their journey.",
            perks: ["Full seasonal kit", "Comp entry reimbursements", "Ambassador page feature"],
            terms: "Monthly escrow, released against 4 tracked posts per month.",
            score: 91
        ),
        WhisperTourBrand(
            id: "sample-forge",
            name: "Forge Recovery Lab",
            handle: "forgerecovery",
            industry: "Recovery tech",
            payText: "$3,000–$9,000",
            basisText: "per year",
            minFollowers: "10,000+ followers",
            about: "Percussion + cold therapy gear. We work with coaches and athletes on long-term yearly partnerships.",
            perks: ["Full recovery suite (kept)", "Affiliate revenue share", "Clinic referrals"],
            terms: "Quarterly escrow releases against agreed content calendar.",
            score: 89
        ),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Self.brands) { brand in
                brandCard(brand)
            }
            Text("SAMPLE BRANDS — THE LIVE MARKETPLACE HAS REAL OFFERS")
                .font(.system(size: 7.5, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
        }
    }

    private func brandCard(_ brand: WhisperTourBrand) -> some View {
        let isExpanded = expandedID == brand.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(duration: 0.32, bounce: 0.2)) {
                    expandedID = isExpanded ? nil : brand.id
                }
            } label: {
                HStack(spacing: 10) {
                    Text(String(brand.name.prefix(1)))
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Self.accent.opacity(0.22), in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(brand.name)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        }
                        Text("\(brand.industry) · \(brand.minFollowers)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(brand.payText)
                            .font(.system(size: 12.5, weight: .black))
                            .foregroundStyle(Self.accent)
                        Text(brand.basisText)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(brand.about)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineSpacing(3)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(brand.perks, id: \.self) { perk in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                                Text(perk)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Self.accent)
                        Text(brand.terms)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    HStack(spacing: 8) {
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(duration: 0.3)) {
                                _ = appliedIDs.insert(brand.id)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: appliedIDs.contains(brand.id) ? "checkmark.circle.fill" : "paperplane.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(appliedIDs.contains(brand.id) ? "Application sent (sample)" : "Apply — sample flow")
                                    .font(.system(size: 11.5, weight: .bold))
                            }
                            .foregroundStyle(appliedIDs.contains(brand.id) ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                appliedIDs.contains(brand.id) ? AnyShapeStyle(Color.green.opacity(0.25)) : AnyShapeStyle(Self.accent),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("JASPER \(brand.score)/100")
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.4)
                        }
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isExpanded ? Self.accent.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Standalone in-meeting tool sheets

/// The WPP calculator as a meeting tool sheet (menu: "WPP calculator").
struct WhisperMeetingWppSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Real partner tiers — drag the sliders, the math is live.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    WhisperWppCalculatorCard()
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("WPP calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The brand marketplace cards as a meeting tool sheet (menu: "Brand cards").
struct WhisperMeetingBrandsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("The actual sponsor cards from the pitch deck — tap one open.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    WhisperTourBrandCards()
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Brand marketplace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
