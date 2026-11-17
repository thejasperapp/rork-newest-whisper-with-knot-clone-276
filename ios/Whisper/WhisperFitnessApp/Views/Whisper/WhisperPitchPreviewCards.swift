import SwiftUI

/// Interactive preview cards used inside the native recruiter pitch decks.
/// Each card is a self-contained mini demo of a real Whisper feature so
/// recruiters can walk prospects through the app without leaving the deck.
/// The cards are now audience-specific: creators see the WPP calculator +
/// brand marketplace, brands see the brand directory + dashboard, coaches see
/// the earnings calculator, and recruiters see the pipeline.
struct WhisperPitchPreviewCards: View {
    @Environment(\.colorScheme) private var colorScheme
    let audience: WhisperPitchAudience

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch audience.id {
            case "creators", "athletes":
                WppCalculatorCard(accent: audience.accent)
                BrandMarketplaceCard(accent: audience.accent)
            case "brands":
                BrandMarketplaceCard(accent: audience.accent)
                BrandDashboardCard(accent: audience.accent)
            case "coaches":
                CoachEarningsCalculatorCard(accent: audience.accent)
                CoachStepsCard(accent: audience.accent)
            case "recruiters":
                RecruiterPipelineCard(accent: audience.accent)
            default:
                BrandMarketplaceCard(accent: audience.accent)
                CoachEarningsCalculatorCard(accent: audience.accent)
            }
        }
    }
}

// MARK: - WPP calculator

private struct WppTier: Identifiable {
    let id: String
    let name: String
    let minFollowers: Int
    let rpmCents: Int
    let perks: [String]
}

private let wppTiers: [WppTier] = [
    WppTier(
        id: "partner",
        name: "Partner",
        minFollowers: 1_000,
        rpmCents: 90,
        perks: ["Ad revenue share on Reels & threads", "Monthly payout via Stripe"]
    ),
    WppTier(
        id: "plus",
        name: "Partner+",
        minFollowers: 10_000,
        rpmCents: 140,
        perks: ["Higher RPM on all formats", "Priority brand placement", "Partner support"]
    ),
    WppTier(
        id: "elite",
        name: "Elite",
        minFollowers: 100_000,
        rpmCents: 220,
        perks: ["Top RPM tier", "First access to premium campaigns", "Custom brand intros"]
    )
]

private struct WppCalculatorCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var followers: Double = 12_000
    @State private var views: Double = 250_000
    let accent: Color

    private var tier: WppTier {
        let eligible = wppTiers.filter { followers >= Double($0.minFollowers) }
        return eligible.last ?? wppTiers[0]
    }

    private var eligible: Bool { followers >= Double(wppTiers[0].minFollowers) }

    private var payoutCents: Int {
        Int(round((views / 1000) * Double(tier.rpmCents)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption.weight(.bold))
                Text("WPP calculator")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                Spacer()
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            VStack(alignment: .leading, spacing: 10) {
                sliderRow(label: "Followers", value: $followers, range: 0...250_000, step: 500)
                sliderRow(label: "Monthly qualified views", value: $views, range: 0...5_000_000, step: 10_000)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption2.weight(.bold))
                    Text("Estimated WPP payout")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                }
                .opacity(0.7)

                if eligible {
                    Text(formatUsd(payoutCents))
                        .font(.system(size: 28, weight: .black))
                    Text("\(tier.name) tier · \(formatUsd(tier.rpmCents)) per 1k views · paid monthly via Stripe")
                        .font(.caption)
                } else {
                    Text("WPP opens at \(wppTiers[0].minFollowers.formatted()) followers — drag the slider up to see earnings.")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 14))
            .foregroundStyle(WhisperTheme.surface(colorScheme))

            HStack(spacing: 8) {
                ForEach(wppTiers) { t in
                    let active = t.id == tier.id && eligible
                    Button {
                        Haptics.tap()
                        followers = Double(t.minFollowers)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(t.name)
                                    .font(.caption.weight(.bold))
                                Spacer()
                                if active {
                                    Image(systemName: "trending.up")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            Text("\(compactNumber(t.minFollowers))+ followers · \(formatUsd(t.rpmCents))/1k")
                                .font(.caption2)
                                .opacity(active ? 0.85 : 1)
                            ForEach(t.perks, id: \.self) { perk in
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(perk)
                                        .font(.system(size: 10, weight: .medium))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(active ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                        .foregroundStyle(active ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(active ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(compactNumber(Int(value.wrappedValue)))
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            Slider(value: value, in: range, step: step)
                .tint(accent)
        }
    }
}

// MARK: - Brand marketplace + apply demo

private struct SampleBrand: Identifiable {
    let id: String
    let companyName: String
    let industry: String
    let minFollowers: Int
    let minAge: Int
    let typicalPay: String
    let accent: Color
}

private let sampleBrands: [SampleBrand] = [
    SampleBrand(
        id: "sample-apex",
        companyName: "Apex Protein",
        industry: "Sports nutrition",
        minFollowers: 5_000,
        minAge: 18,
        typicalPay: "$250–500 per post",
        accent: Color(red: 0.88, green: 0.11, blue: 0.28)
    ),
    SampleBrand(
        id: "sample-stride",
        companyName: "Stride Wear",
        industry: "Activewear",
        minFollowers: 10_000,
        minAge: 18,
        typicalPay: "$500–1,000 per post",
        accent: Color(red: 0.13, green: 0.55, blue: 0.96)
    ),
    SampleBrand(
        id: "sample-forge",
        companyName: "Forge Recovery",
        industry: "Recovery tech",
        minFollowers: 2_500,
        minAge: 18,
        typicalPay: "$150–300 per post",
        accent: Color(red: 0.97, green: 0.45, blue: 0.30)
    )
]

private struct BrandMarketplaceCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color
    @State private var selectedBrand: SampleBrand?
    @State private var appliedBrandIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "storefront")
                    .font(.caption.weight(.bold))
                Text("Brand marketplace")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                Spacer()
                Text("Live preview")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            VStack(spacing: 10) {
                ForEach(sampleBrands) { brand in
                    Button {
                        Haptics.tap()
                        selectedBrand = brand
                    } label: {
                        brandRow(brand)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .sheet(item: $selectedBrand) { brand in
            BrandApplySheet(brand: brand, applied: appliedBrandIDs.contains(brand.id)) {
                appliedBrandIDs.insert(brand.id)
            }
        }
    }

    private func brandRow(_ brand: SampleBrand) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(brand.accent.opacity(0.15))
                Image(systemName: "bag.fill")
                    .font(.title2)
                    .foregroundStyle(brand.accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(brand.companyName)
                        .font(.subheadline.weight(.bold))
                    Image(systemName: "briefcase.fill")
                        .font(.caption2)
                        .foregroundStyle(brand.accent)
                    if appliedBrandIDs.contains(brand.id) {
                        Text("Applied")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.13, green: 0.65, blue: 0.36).opacity(0.12), in: Capsule())
                    }
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(brand.industry)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text("Typically pays \(brand.typicalPay)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(12)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

private struct BrandApplySheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let brand: SampleBrand
    let applied: Bool
    let onApply: () -> Void

    @State private var amount: String = ""
    @State private var age: String = ""
    @State private var message: String = ""
    @State private var sending: Bool = false
    @State private var sent: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(brand.accent.opacity(0.15))
                                Image(systemName: "bag.fill")
                                    .font(.title2)
                                    .foregroundStyle(brand.accent)
                            }
                            .frame(width: 64, height: 64)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(brand.companyName)
                                    .font(.title3.weight(.bold))
                                Text(brand.industry)
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.13))
                                    Text("Jasper verified brand")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.13))
                                }
                            }
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sponsorship requirements")
                                .font(.subheadline.weight(.bold))
                            HStack(spacing: 8) {
                                Image(systemName: "person.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                Text("\(brand.minFollowers.formatted())+ followers")
                                    .font(.caption)
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                Text("\(brand.minAge)+ years old")
                                    .font(.caption)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }

                        if applied || sent {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                                Text("Application sent (demo)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.13, green: 0.65, blue: 0.36).opacity(0.10), in: .rect(cornerRadius: 14))
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Apply for sponsorship")
                                    .font(.subheadline.weight(.bold))

                                HStack(spacing: 8) {
                                    Text("$")
                                        .font(.subheadline)
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    TextField("250", text: $amount)
                                        .keyboardType(.decimalPad)
                                        .font(.subheadline)
                                    Text("per post")
                                        .font(.caption)
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }

                                TextField("Your age", text: $age)
                                    .keyboardType(.numberPad)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                    }

                                TextField("Why you're a great fit…", text: $message, axis: .vertical)
                                    .font(.subheadline)
                                    .lineLimit(2...4)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                    }

                                Button {
                                    Haptics.success()
                                    sending = true
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(700))
                                        await MainActor.run {
                                            sending = false
                                            sent = true
                                            onApply()
                                        }
                                    }
                                } label: {
                                    HStack {
                                        if sending {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "paperplane.fill")
                                            Text("Send application")
                                        }
                                    }
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(brand.accent, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(sending || amount.isEmpty || age.isEmpty)
                                .opacity((sending || amount.isEmpty || age.isEmpty) ? 0.5 : 1)
                            }
                        }

                        Text("Sample brand for presentation. On real deals funds are escrowed and released when tracked posts go live — Whisper keeps 10%.")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Brand profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }
}

// MARK: - Brand dashboard demo

private struct BrandDashboardCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color

    private let applications: [(name: String, status: String, amount: String)] = [
        ("@alex.fit", "pending", "$350 per post"),
        ("@maya.lifts", "countered", "$500 per post"),
        ("@jordan.runs", "accepted", "$200 per post")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.caption.weight(.bold))
                Text("Brand dashboard")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                Spacer()
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    dashboardStat(label: "Applications", value: "3", color: accent)
                    dashboardStat(label: "In escrow", value: "$1,050", color: Color(red: 0.96, green: 0.62, blue: 0.04))
                    dashboardStat(label: "Released", value: "$400", color: Color(red: 0.13, green: 0.65, blue: 0.36))
                }

                Text("Open applications")
                    .font(.caption.weight(.bold))
                    .padding(.top, 4)

                ForEach(applications, id: \.name) { app in
                    HStack(spacing: 10) {
                        WhisperAvatar(username: app.name, size: 32, ring: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.subheadline.weight(.semibold))
                            Text(app.amount)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        Spacer()
                        Text(app.status.capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor(app.status))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor(app.status).opacity(0.12), in: Capsule())
                    }
                    .padding(10)
                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func dashboardStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "accepted": return Color(red: 0.13, green: 0.65, blue: 0.36)
        case "countered": return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "pending": return Color(red: 0.96, green: 0.62, blue: 0.04)
        default: return WhisperTheme.muted(colorScheme)
        }
    }
}

// MARK: - Coach earnings calculator

private struct CoachEarningsCalculatorCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color

    @State private var rate: Double = 150
    @State private var clients: Double = 10

    private var grossCents: Int { Int(rate * clients * 100) }
    private var feeCents: Int { Int(round(Double(grossCents) * 0.10)) }
    private var netCents: Int { grossCents - feeCents }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption.weight(.bold))
                Text("Coach earnings")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                Spacer()
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            VStack(alignment: .leading, spacing: 10) {
                sliderRow(label: "Monthly rate", value: $rate, range: 5...2000, step: 5, suffix: "$")
                sliderRow(label: "Active clients", value: $clients, range: 1...100, step: 1, suffix: nil)
            }

            VStack(spacing: 6) {
                HStack {
                    Text("Gross subscriptions")
                        .font(.caption)
                    Spacer()
                    Text(formatUsd(grossCents) + "/mo")
                        .font(.caption.weight(.semibold))
                }
                HStack {
                    Text("Whisper fee (10%)")
                        .font(.caption)
                    Spacer()
                    Text("−" + formatUsd(feeCents))
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(12)
            .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("You take home")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .opacity(0.7)
                Text(formatUsd(netCents))
                    .font(.system(size: 28, weight: .black))
                Text("Paid out by Stripe on a rolling basis · no listing fees")
                    .font(.caption)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 14))
            .foregroundStyle(WhisperTheme.surface(colorScheme))
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let suffix {
                    Text("\(suffix)\(Int(value.wrappedValue))")
                        .font(.subheadline.weight(.bold))
                } else {
                    Text("\(Int(value.wrappedValue))")
                        .font(.subheadline.weight(.bold))
                }
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            Slider(value: value, in: range, step: step)
                .tint(accent)
        }
    }
}

private struct CoachStepsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color
    @State private var activeStep: Int = 0

    private let steps: [(icon: String, title: String, body: String)] = [
        ("dollarsign.circle", "Set your monthly rate", "Pick any rate from $5 to $2,000/month. Change it anytime."),
        ("building.columns.fill", "Link your bank once", "Stripe onboarding takes ~2 minutes. Payouts go straight to your bank."),
        ("person.badge.plus", "Clients hire you in-app", "Anyone taps Hire on your profile and subscribes with Apple Pay or a card."),
        ("banknote.fill", "You get paid automatically", "90% of each subscription lands in your Stripe balance every month.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.caption.weight(.bold))
                Text("How coaching works")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                Spacer()
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            VStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    let active = activeStep == idx
                    Button {
                        Haptics.tap()
                        activeStep = idx
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(active ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                                Image(systemName: step.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(active ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                            }
                            .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(idx + 1). \(step.title)")
                                    .font(.subheadline.weight(.bold))
                                Text(step.body)
                                    .font(.caption)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(active ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                        .padding(12)
                        .background(active ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(active ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

// MARK: - Recruiter pipeline demo

private struct RecruiterPipelineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color

    private let stages: [(label: String, count: Int, color: Color)] = [
        ("Discovered", 4, Color(red: 0.42, green: 0.45, blue: 0.50)),
        ("Contacted", 3, Color(red: 0.23, green: 0.51, blue: 0.96)),
        ("Interested", 2, Color(red: 0.66, green: 0.33, blue: 0.91)),
        ("Meeting", 2, Color(red: 0.96, green: 0.62, blue: 0.04)),
        ("Ready", 1, Color(red: 0.13, green: 0.77, blue: 0.37)),
        ("Promoted", 1, Color(red: 0.13, green: 0.65, blue: 0.36))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.caption.weight(.bold))
                Text("Prospect pipeline")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                Spacer()
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            VStack(spacing: 8) {
                ForEach(stages, id: \.label) { stage in
                    HStack(spacing: 10) {
                        Text(stage.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 76, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(WhisperTheme.hairline(colorScheme).opacity(0.4))
                                Capsule()
                                    .fill(stage.color)
                                    .frame(width: max(6, geo.size.width * CGFloat(stage.count) / 4.0))
                            }
                        }
                        .frame(height: 8)
                        Text("\(stage.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

// MARK: - Helpers

private func formatUsd(_ cents: Int) -> String {
    let dollars = Double(cents) / 100.0
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = cents % 100 == 0 ? 0 : 2
    return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
}

private func compactNumber(_ n: Int) -> String {
    if n >= 1_000_000 {
        return String(format: "%.1fM", Double(n) / 1_000_000)
    } else if n >= 1_000 {
        return String(format: "%.1fK", Double(n) / 1_000)
    }
    return "\(n)"
}

#Preview {
    WhisperPitchPreviewCards(audience: whisperPitchAudiences[1])
        .padding()
}
