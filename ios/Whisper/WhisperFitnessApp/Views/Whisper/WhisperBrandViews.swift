import SwiftUI
import PhotosUI

// MARK: - Entrance animation

extension View {
    /// Staggered entrance: fades and slides content in when `appeared` flips
    /// to true, delayed by `index` so rows cascade top-to-bottom.
    func entrance(_ appeared: Bool, index: Int) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(index) * 0.06),
                value: appeared
            )
    }
}

// MARK: - Brand directory

/// Public directory of sponsor brands. Creators browse brands, see their
/// requirements and typical pay, and apply from the detail view.
struct WhisperBrandDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var brands: [WhisperBrandProfile] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedBrand: WhisperBrandProfile?
    @State private var searchText: String = ""
    @State private var selectedIndustry: String?
    /// Drives the staggered entrance run-through when the marketplace opens.
    @State private var appeared: Bool = false

    /// Distinct industries present in the directory, for the filter row.
    private var industries: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for b in brands {
            let industry = (b.industry ?? "").trimmingCharacters(in: .whitespaces)
            guard !industry.isEmpty, seen.insert(industry.lowercased()).inserted else { continue }
            out.append(industry)
        }
        return out.sorted()
    }

    private var filteredBrands: [WhisperBrandProfile] {
        brands.filter { brand in
            if let industry = selectedIndustry,
               (brand.industry ?? "").caseInsensitiveCompare(industry) != .orderedSame {
                return false
            }
            let query = searchText.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return true }
            return brand.companyName.localizedStandardContains(query)
                || (brand.industry ?? "").localizedStandardContains(query)
                || (brand.about ?? "").localizedStandardContains(query)
        }
    }

    /// The spotlight brand — first Jasper-verified brand with a pay range,
    /// falling back to the first brand.
    private var featuredBrand: WhisperBrandProfile? {
        guard searchText.isEmpty, selectedIndustry == nil else { return nil }
        return brands.first { $0.emberVerified && $0.typicalPayText != nil } ?? brands.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        marqueeHeader
                            .entrance(appeared, index: 0)
                        searchBar
                            .entrance(appeared, index: 1)
                        if !industries.isEmpty {
                            industryChips
                                .entrance(appeared, index: 2)
                        }
                        if isLoading && brands.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(WhisperTheme.ink(colorScheme))
                                Spacer()
                            }
                            .padding(.top, 60)
                        } else if brands.isEmpty, errorMessage != nil {
                            VStack(spacing: 12) {
                                Text("Couldn’t load brands").font(.headline)
                                Text("Check your connection and try again.").font(.subheadline).foregroundStyle(.secondary)
                                Button("Try again") { Task { await load() } }.frame(minHeight: 44)
                            }.frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else if filteredBrands.isEmpty {
                            emptyState
                        } else {
                            if let featured = featuredBrand {
                                featuredCard(featured)
                                    .entrance(appeared, index: 3)
                            }
                            let rest = filteredBrands.filter { $0.id != featuredBrand?.id }
                            if !rest.isEmpty {
                                Text(selectedIndustry.map { $0.uppercased() } ?? "ALL BRANDS")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .kerning(0.8)
                                    .padding(.top, 2)
                                    .entrance(appeared, index: 4)
                                VStack(spacing: 12) {
                                    ForEach(Array(rest.enumerated()), id: \.element.id) { pair in
                                        Button {
                                            Haptics.tap()
                                            selectedBrand = pair.element
                                        } label: {
                                            WhisperBrandCard(brand: pair.element)
                                        }
                                        .buttonStyle(.plain)
                                        .entrance(appeared, index: 5 + min(pair.offset, 6))
                                    }
                                }
                            }
                        }
                        if errorMessage != nil, !brands.isEmpty {
                            Button("Couldn’t refresh brands. Try again") { Task { await load() } }
                                .font(.footnote).frame(minHeight: 44)
                        }
                        trustFooter
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Brand Marketplace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            // Push the brand profile as a full screen instead of stacking a
            // second modal — the marketplace reads as one place, not sheets.
            .navigationDestination(item: $selectedBrand) { brand in
                WhisperBrandDetailView(brand: brand, isPushed: true)
            }
        }
        .task {
            await load()
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                appeared = true
            }
        }
    }

    /// Editorial masthead — big serif-feel headline over an ink panel.
    private var marqueeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GET SPONSORED")
                .font(.system(size: 28, weight: .black))
                .kerning(-0.5)
                .foregroundStyle(WhisperTheme.surface(colorScheme))
            Text("Real brands. Real pay ranges. Escrow-protected deals, checked by Jasper before they reach you.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.surface(colorScheme).opacity(0.75))
            HStack(spacing: 6) {
                marqueeChip("lock.shield.fill", "Escrow")
                marqueeChip("dollarsign.circle.fill", "Transparent pay")
                marqueeChip("flame.fill", "Jasper checked")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 22))
    }

    private func marqueeChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(WhisperTheme.surface(colorScheme), in: Capsule())
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search brands, industries…", text: $searchText)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    Haptics.tap()
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var industryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                industryChip(nil, label: "All")
                ForEach(industries, id: \.self) { industry in
                    industryChip(industry, label: industry)
                }
            }
        }
        .contentMargins(.horizontal, 0)
    }

    private func industryChip(_ value: String?, label: String) -> some View {
        let selected = selectedIndustry == value
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3)) {
                selectedIndustry = value
            }
        } label: {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme), in: Capsule())
                .overlay {
                    if !selected {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// Spotlight card for the featured brand — bigger logo, pay range front
    /// and center.
    private func featuredCard(_ brand: WhisperBrandProfile) -> some View {
        Button {
            Haptics.tap()
            selectedBrand = brand
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("FEATURED PARTNER")
                        .font(.system(size: 10, weight: .black))
                        .kerning(1)
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                HStack(spacing: 14) {
                    brandLogo(brand, size: 64, cornerRadius: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(brand.companyName)
                            .font(.title3.weight(.black))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(1)
                        if let industry = brand.industry, !industry.isEmpty {
                            Text(industry)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        if brand.emberVerified {
                            emberBadge
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let about = brand.about, !about.isEmpty {
                    Text(about)
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                        .lineLimit(2)
                }
                HStack {
                    if let pay = brand.typicalPayText {
                        // Quiet, editorial pay line — no oversized price type.
                        HStack(spacing: 5) {
                            Image(systemName: "dollarsign.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Text("Typically pays \(pay)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                        }
                    }
                    Spacer()
                    Text("View deal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
            }
            .padding(16)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(WhisperTheme.ink(colorScheme).opacity(0.25), lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var emberBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Jasper verified")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.12), in: Capsule())
    }

    private var trustFooter: some View {
        Text("Every deal funds into escrow before you post — you always know the pay, the deliverables, and that the money is real.")
            .font(.caption2)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: searchText.isEmpty ? "building.2" : "magnifyingglass", height: 144)
            Text(searchText.isEmpty ? "No brands yet" : "No matches")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(searchText.isEmpty
                 ? "Brands that join Whisper appear here with their sponsorship requirements and typical pay — so you always know what a partnership is worth."
                 : "Try a different name or clear the industry filter.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func brandLogo(_ brand: WhisperBrandProfile, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Color(.secondarySystemBackground)
            .frame(width: size, height: size)
            .overlay {
                if let url = WhisperFeaturedProfile.resolvePhotoURL(brand.logoUrl) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        default:
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                } else {
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private func load() async {
        guard !isLoading else { return }
        let generation = AccountStorage.generation
        isLoading = true
        errorMessage = nil
        defer { if generation == AccountStorage.generation { isLoading = false } }
        do {
            let rows = try await WhisperBrandService.shared.fetchBrands()
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            brands = rows
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            errorMessage = "Couldn’t load brands. Please try again."
        }
    }
}

// MARK: - Brand card

/// Compact directory card: logo, company, industry, requirement chips, and
/// the transparent typical-pay line.
struct WhisperBrandCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let brand: WhisperBrandProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                logoPanel
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(brand.companyName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(1)
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .frame(width: 16, height: 16)
                            .background(WhisperTheme.ink(colorScheme), in: Circle())
                    }
                    if brand.emberVerified {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("Jasper verified")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                    if let industry = brand.industry, !industry.isEmpty {
                        Text(industry)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                    if let pay = brand.typicalPayText {
                        Text("Typically pays \(pay)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            HStack(spacing: 6) {
                requirementChip("\(brand.minFollowers.formatted()) followers")
                requirementChip("\(brand.minAge)+")
                if brand.minPosts > 0 {
                    requirementChip("\(brand.minPosts)+ posts")
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .contentShape(.rect)
    }

    private var logoPanel: some View {
        Color(.secondarySystemBackground)
            .frame(width: 52, height: 52)
            .overlay {
                if let url = WhisperFeaturedProfile.resolvePhotoURL(brand.logoUrl) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        default:
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                } else {
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .clipShape(.rect(cornerRadius: 12))
    }

    private func requirementChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
    }
}

// MARK: - Brand detail + apply

/// Full brand profile: about, amenities, requirements, transparent pay, and
/// the sponsorship apply button (gated by the brand's requirements).
struct WhisperBrandDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let brand: WhisperBrandProfile
    /// True when this view is pushed onto an existing NavigationStack (the
    /// marketplace). False (default) when presented modally on its own.
    var isPushed: Bool = false

    @State private var eligibility: WhisperSponsorEligibility?
    @State private var isLoadingEligibility: Bool = false
    @State private var showApply: Bool = false
    @State private var applied: Bool = false
    @State private var errorMessage: String?

    private var isMe: Bool {
        brand.userId.lowercased() == AccountStorage.currentUserID.lowercased()
    }

    var body: some View {
        if isPushed {
            detailBody
        } else {
            NavigationStack {
                detailBody
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { dismiss() }
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                        }
                    }
            }
        }
    }

    private var detailBody: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let about = brand.about, !about.isEmpty {
                        Text(about)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineSpacing(4)
                    }

                    if brand.emberSummary != nil || brand.emberVerified {
                        emberCheckCard
                    }

                    requirementsCard
                    payTransparencyCard

                    if !brand.amenities.isEmpty {
                        amenitiesCard
                    }

                    if !isMe {
                        applySection
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle(brand.companyName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showApply) {
            WhisperBrandApplySheet(brand: brand) {
                applied = true
            }
        }
        .task { await loadEligibility() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Color(.secondarySystemBackground)
                .frame(width: 72, height: 72)
                .overlay {
                    if let url = WhisperFeaturedProfile.resolvePhotoURL(brand.logoUrl) {
                        WhisperCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            default:
                                Image(systemName: "building.2.fill")
                                    .font(.title2)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                    } else {
                        Image(systemName: "building.2.fill")
                            .font(.title2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(brand.companyName)
                        .font(.title3.weight(.black))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(width: 18, height: 18)
                        .background(WhisperTheme.ink(colorScheme), in: Circle())
                }
                if let industry = brand.industry, !industry.isEmpty {
                    Text(industry)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                if let website = brand.website, !website.isEmpty,
                   let url = URL(string: website.hasPrefix("http") ? website : "https://\(website)") {
                    Button {
                        Haptics.tap()
                        WhisperInAppBrowser.shared.open(url)
                    } label: {
                        HStack(spacing: 3) {
                            Text(website.replacingOccurrences(of: "https://", with: ""))
                                .lineLimit(1)
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var emberCheckCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.orange)
                Text(brand.emberVerified ? "Jasper verified this brand" : "Jasper checked this brand")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if let score = brand.emberScore {
                    Text("\(score)/100")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.orange)
                }
            }
            if let summary = brand.emberSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineSpacing(3)
            }
            if let handle = brand.instagram, !handle.isEmpty {
                Button {
                    Haptics.tap()
                    if let url = URL(string: "https://instagram.com/\(handle)") {
                        WhisperInAppBrowser.shared.open(url)
                    }
                } label: {
                    Text("@\(handle) on Instagram")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        }
    }

    private var requirementsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sponsorship requirements")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            requirementRow(icon: "person.2.fill", text: "\(brand.minFollowers.formatted())+ followers")
            requirementRow(icon: "calendar", text: "\(brand.minAge)+ years old")
            if brand.minPosts > 0 {
                requirementRow(icon: "square.grid.2x2", text: "\(brand.minPosts)+ posts")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func requirementRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                .frame(width: 20)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
    }

    private var payTransparencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                Text("Payment transparency")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            if let pay = brand.typicalPayText {
                Text("This brand typically pays \(pay)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            } else {
                Text("This brand hasn't shared a typical pay range yet.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            if let terms = brand.paymentTerms, !terms.isEmpty {
                Text(terms)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineSpacing(3)
            }
            Text("Payments are held by Whisper and only released to you once your sponsored posts are live — so you never chase an invoice.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var amenitiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What this brand uses")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(brand.amenities, id: \.self) { amenity in
                    Text(amenity)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var applySection: some View {
        if applied {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                Text("Application sent — track it in Sponsorships.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 0.13, green: 0.65, blue: 0.36).opacity(0.1), in: Capsule())
        } else if isLoadingEligibility {
            ProgressView()
                .tint(WhisperTheme.ink(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else if let eligibility, !eligibility.eligible {
            VStack(alignment: .leading, spacing: 6) {
                Text("You're not eligible to apply yet")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                ForEach(eligibility.reasons, id: \.self) { reason in
                    Text("• \(reason)")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        } else {
            Button {
                Haptics.tap()
                showApply = true
            } label: {
                Text("Apply for sponsorship")
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
            }
            .buttonStyle(.plain)
        }
    }

    private func loadEligibility() async {
        guard !isMe else { return }
        isLoadingEligibility = true
        defer { isLoadingEligibility = false }
        do {
            eligibility = try await WhisperBrandService.shared.fetchEligibility(brandUserId: brand.userId)
        } catch {
            // Eligibility is a soft gate client-side; the backend re-checks.
            eligibility = nil
        }
    }
}

// MARK: - Apply sheet

/// The sponsorship application form: collaboration basis (dropdown), the
/// desired amount (fill-in), age confirmation, and a pitch message.
struct WhisperBrandApplySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let brand: WhisperBrandProfile
    var onApplied: () -> Void = {}

    @State private var basis: WhisperSponsorBasis = .perPost
    @State private var amountString: String = ""
    @State private var ageString: String = ""
    @State private var message: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Tell \(brand.companyName) what you're looking for. They can accept, send different terms, or pass.")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("How do you want to collaborate?")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Picker("Basis", selection: $basis) {
                                ForEach(WhisperSponsorBasis.allCases) { b in
                                    Text(b.displayName).tag(b)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Desired amount")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            HStack(spacing: 4) {
                                Text("$")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                TextField("250", text: $amountString)
                                    .font(.title3.weight(.bold))
                                    .keyboardType(.decimalPad)
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text(basis.shortLabel)
                                    .font(.footnote)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            .padding(14)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                            if let pay = brand.typicalPayText {
                                Text("Heads-up: this brand typically pays \(pay).")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your age")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            TextField("18", text: $ageString)
                                .font(.body.weight(.semibold))
                                .keyboardType(.numberPad)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .padding(14)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            Text("\(brand.companyName) requires partners to be \(brand.minAge)+.")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pitch (optional)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            TextField("Why you're a great fit…", text: $message, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.subheadline)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .padding(14)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                        }

                        Button {
                            Haptics.tap()
                            Task { await submit() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView().tint(WhisperTheme.surface(colorScheme))
                                }
                                Text("Send application")
                                    .font(.body.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(WhisperTheme.ink(colorScheme), in: Capsule())
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting || amountString.isEmpty || ageString.isEmpty)

                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Apply for Sponsorship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func submit() async {
        let cleanedAmount = amountString
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(cleanedAmount), dollars >= 1 else {
            errorMessage = "Enter a valid amount."
            return
        }
        guard let age = Int(ageString.trimmingCharacters(in: .whitespaces)), age >= brand.minAge else {
            errorMessage = "You must be \(brand.minAge) or older to apply to this brand."
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await WhisperBrandService.shared.apply(
                brandUserId: brand.userId,
                basis: basis,
                amountCents: Int((dollars * 100).rounded()),
                message: message,
                age: age
            )
            Haptics.success()
            onApplied()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Brand editor (signup)

/// The brand signup / profile editor: company details, amenities, the
/// sponsorship requirements that gate applicants, and transparent pay.
struct WhisperBrandEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var brands = WhisperBrandService.shared

    @State private var companyName: String = ""
    @State private var website: String = ""
    @State private var industry: String = ""
    @State private var about: String = ""
    @State private var logoUrl: String = ""
    @State private var instagram: String = ""
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var isUploadingLogo: Bool = false
    @State private var isVerifying: Bool = false
    @State private var verifyResult: WhisperEmberBrandVerdict?
    @State private var amenities: Set<String> = []
    @State private var minFollowersString: String = "1000"
    @State private var minAgeString: String = "18"
    @State private var minPostsString: String = "10"
    @State private var payBasis: WhisperSponsorBasis = .perPost
    @State private var payMinString: String = ""
    @State private var payMaxString: String = ""
    @State private var paymentTerms: String = ""
    @State private var published: Bool = true

    @State private var isSaving: Bool = false
    @State private var saved: Bool = false
    @State private var errorMessage: String?



    private static let amenityOptions: [String] = [
        "Creator analytics",
        "Campaign tracking",
        "Creator discovery",
        "Content approvals",
        "Product seeding",
        "Affiliate links",
        "Contract templates",
        "Dedicated support",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionCard(title: "Company") {
                            logoPickerRow
                            labeledField("Company name", text: $companyName, placeholder: "Acme Nutrition")
                            labeledField("Website", text: $website, placeholder: "acme.com")
                            labeledField("Industry", text: $industry, placeholder: "Supplements")
                            labeledField("Instagram handle", text: $instagram, placeholder: "acmenutrition")
                            VStack(alignment: .leading, spacing: 6) {
                                Text("About")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                TextField("What your brand does and what you look for in creators…", text: $about, axis: .vertical)
                                    .lineLimit(3...6)
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                    }
                            }
                        }

                        emberVerificationCard

                        sectionCard(title: "Tools you need") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                                ForEach(Self.amenityOptions, id: \.self) { option in
                                    Button {
                                        Haptics.tap()
                                        if amenities.contains(option) {
                                            amenities.remove(option)
                                        } else {
                                            amenities.insert(option)
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: amenities.contains(option) ? "checkmark.circle.fill" : "circle")
                                                .font(.caption)
                                            Text(option)
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(amenities.contains(option) ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(
                                                    amenities.contains(option) ? WhisperTheme.ink(colorScheme).opacity(0.5) : WhisperTheme.hairline(colorScheme),
                                                    lineWidth: 1
                                                )
                                        }
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        sectionCard(title: "Sponsorship requirements") {
                            Text("Only creators who meet these can apply — it keeps your inbox high-signal.")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            labeledField("Minimum followers", text: $minFollowersString, placeholder: "1000", keyboard: .numberPad)
                            labeledField("Minimum age", text: $minAgeString, placeholder: "18", keyboard: .numberPad)
                            labeledField("Minimum posts", text: $minPostsString, placeholder: "10", keyboard: .numberPad)
                        }

                        sectionCard(title: "Payment transparency") {
                            Text("Creators see this before applying. Transparent brands get better applicants.")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Picker("Basis", selection: $payBasis) {
                                ForEach(WhisperSponsorBasis.allCases) { b in
                                    Text(b.displayName).tag(b)
                                }
                            }
                            .pickerStyle(.segmented)
                            HStack(spacing: 10) {
                                labeledField("Typical min ($)", text: $payMinString, placeholder: "100", keyboard: .decimalPad)
                                labeledField("Typical max ($)", text: $payMaxString, placeholder: "500", keyboard: .decimalPad)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Payment terms")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                TextField("e.g. Paid per approved post, released weekly…", text: $paymentTerms, axis: .vertical)
                                    .lineLimit(2...4)
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                    }
                            }
                        }

                        sectionCard(title: "Visibility") {
                            Toggle(isOn: $published) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Listed in the brand directory")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    Text("Creators can find you and apply.")
                                        .font(.caption)
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                            }
                            .tint(WhisperTheme.ink(colorScheme))
                        }

                        Button {
                            Haptics.tap()
                            Task { await save() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView().tint(WhisperTheme.surface(colorScheme))
                                }
                                Text(brands.myBrand == nil ? "Create brand profile" : "Save brand profile")
                                    .font(.body.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(WhisperTheme.ink(colorScheme), in: Capsule())
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || companyName.trimmingCharacters(in: .whitespaces).isEmpty)

                        if saved {
                            Text("Saved — creators can now find your brand and apply.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Brand Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await hydrate() }
    }

    private var logoPickerRow: some View {
        HStack(spacing: 14) {
            Color(.secondarySystemBackground)
                .frame(width: 64, height: 64)
                .overlay {
                    if let url = WhisperFeaturedProfile.resolvePhotoURL(logoUrl.isEmpty ? nil : logoUrl) {
                        WhisperCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            default:
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                    } else {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                .clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                PhotosPicker(selection: $logoPickerItem, matching: .images) {
                    HStack(spacing: 6) {
                        if isUploadingLogo {
                            ProgressView().tint(WhisperTheme.ink(colorScheme))
                        } else {
                            Image(systemName: "photo.badge.plus")
                        }
                        Text(logoUrl.isEmpty ? "Upload logo" : "Replace logo")
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.ink(colorScheme).opacity(0.08), in: Capsule())
                }
                .disabled(isUploadingLogo)

                if !logoUrl.isEmpty {
                    Button {
                        Haptics.tap()
                        logoUrl = ""
                    } label: {
                        Text("Remove")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: logoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadLogo(newItem) }
        }
    }

    private var emberVerificationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.body)
                    .foregroundStyle(Color.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jasper verification")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Jasper reviews your Instagram's tagged posts and creator collabs — so creators know you're the real deal.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }

            if let result = currentVerdict {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: result.verified ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.caption)
                        Text(result.verified ? "Jasper verified this brand · \(result.score)/100" : "Not verified yet · \(result.score)/100")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(result.verified ? Color(red: 0.13, green: 0.65, blue: 0.36) : Color(red: 0.92, green: 0.63, blue: 0.18))
                    if !result.summary.isEmpty {
                        Text(result.summary)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineSpacing(3)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (result.verified ? Color(red: 0.13, green: 0.65, blue: 0.36) : Color(red: 0.92, green: 0.63, blue: 0.18)).opacity(0.07),
                    in: .rect(cornerRadius: 12)
                )
            }

            Button {
                Haptics.tap()
                Task { await runEmberCheck() }
            } label: {
                HStack(spacing: 8) {
                    if isVerifying {
                        ProgressView().tint(.white)
                        Text("Jasper is reviewing your Instagram…")
                    } else {
                        Image(systemName: "flame.fill")
                        Text(currentVerdict == nil ? "Have Jasper verify my Instagram" : "Run Jasper's check again")
                    }
                }
                .font(.footnote.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.orange, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isVerifying || instagram.trimmingCharacters(in: .whitespaces).isEmpty || companyName.trimmingCharacters(in: .whitespaces).isEmpty || brands.myBrand == nil)

            if brands.myBrand == nil {
                Text("Save your brand profile first, then run Jasper's check.")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.05), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        }
    }

    /// Fresh result from this session, else the saved verdict on the profile.
    private var currentVerdict: WhisperEmberBrandVerdict? {
        if let verifyResult { return verifyResult }
        guard let brand = brands.myBrand,
              brand.emberSummary != nil || brand.emberVerified else { return nil }
        return WhisperEmberBrandVerdict(
            verified: brand.emberVerified,
            score: brand.emberScore ?? 0,
            summary: brand.emberSummary ?? ""
        )
    }

    private func uploadLogo(_ item: PhotosPickerItem) async {
        isUploadingLogo = true
        defer {
            isUploadingLogo = false
            logoPickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            logoUrl = try await WhisperBrandService.shared.uploadLogo(data)
            Haptics.success()
        } catch {
            errorMessage = "Couldn't upload the logo. Try again."
        }
    }

    private func runEmberCheck() async {
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }
        do {
            let verdict = try await WhisperEmberBrandCheck.inspect(
                companyName: companyName,
                instagram: instagram,
                website: website
            )
            try await WhisperBrandService.shared.saveVerification(
                instagram: instagram.trimmingCharacters(in: .whitespaces),
                verified: verdict.verified,
                score: verdict.score,
                summary: verdict.summary
            )
            verifyResult = verdict
            if verdict.verified { Haptics.success() } else { Haptics.warning() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sectionCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField(placeholder, text: text)
                .font(.subheadline)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(12)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
    }

    private func hydrate() async {
        let brand = await brands.refreshMyBrand()
        guard let brand else { return }
        companyName = brand.companyName
        website = brand.website ?? ""
        industry = brand.industry ?? ""
        about = brand.about ?? ""
        logoUrl = brand.logoUrl ?? ""
        instagram = brand.instagram ?? ""
        amenities = Set(brand.amenities)
        minFollowersString = String(brand.minFollowers)
        minAgeString = String(brand.minAge)
        minPostsString = String(brand.minPosts)
        payBasis = brand.basisEnum
        if let lo = brand.typicalPayMinCents { payMinString = String(lo / 100) }
        if let hi = brand.typicalPayMaxCents { payMaxString = String(hi / 100) }
        paymentTerms = brand.paymentTerms ?? ""
        published = brand.published
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        saved = false
        defer { isSaving = false }

        let dollarsToCents = { (raw: String) -> Int? in
            let cleaned = raw.replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let d = Double(cleaned), d > 0 else { return nil }
            return Int((d * 100).rounded())
        }

        var input: [String: Any] = [
            "companyName": companyName.trimmingCharacters(in: .whitespaces),
            "website": website.trimmingCharacters(in: .whitespaces),
            "industry": industry.trimmingCharacters(in: .whitespaces),
            "about": about.trimmingCharacters(in: .whitespaces),
            "logoUrl": logoUrl.trimmingCharacters(in: .whitespaces),
            "instagram": instagram.trimmingCharacters(in: .whitespaces),
            "amenities": Array(amenities).sorted(),
            "minFollowers": Int(minFollowersString) ?? 0,
            "minAge": Int(minAgeString) ?? 18,
            "minPosts": Int(minPostsString) ?? 0,
            "payBasis": payBasis.rawValue,
            "paymentTerms": paymentTerms.trimmingCharacters(in: .whitespaces),
            "published": published,
        ]
        if let lo = dollarsToCents(payMinString) { input["typicalPayMinCents"] = lo }
        if let hi = dollarsToCents(payMaxString) { input["typicalPayMaxCents"] = hi }

        do {
            try await WhisperBrandService.shared.saveBrandProfile(input)
            Haptics.success()
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
