import SwiftUI

/// Jasper's MEETING pitch deck — rendered INLINE wherever the meeting notes
/// live (never a separate popup): a small stack of cream ruled pages with
/// Jasper peeking from BEHIND the top edge, a red margin line, serif ink
/// headings, and highlighter sweeps over the moments that matter. Swipe or
/// use the chips to flip pages. The iOS twin of the web PitchDeckInline.
/// (Distinct from WhisperPitchDeckView, the sales-deck hub for the five
/// public audience decks.)
struct WhisperMeetingDeckView: View {
    let deck: WhisperPitchDeck

    @State private var page: Int = 0

    // Notebook palette — fixed paper colors on any backdrop.
    private let paper = Color(red: 0.984, green: 0.968, blue: 0.925)
    private let paperLine = Color(red: 0.914, green: 0.878, blue: 0.784)
    private let paperEdge = Color(red: 0.937, green: 0.906, blue: 0.824)
    private let paperEdge2 = Color(red: 0.961, green: 0.933, blue: 0.863)
    private let marginRed = Color(red: 0.898, green: 0.655, blue: 0.627)
    private let ink = Color(red: 0.125, green: 0.141, blue: 0.169)
    private let inkSoft = Color(red: 0.361, green: 0.353, blue: 0.314)
    private let mintDeep = Color(red: 0.055, green: 0.624, blue: 0.463)
    private let hiMint = Color(red: 0.741, green: 0.953, blue: 0.863)
    private let hiAmber = Color(red: 0.984, green: 0.906, blue: 0.682)
    private let hiRose = Color(red: 0.976, green: 0.827, blue: 0.796)
    private let roseDeep = Color(red: 0.69, green: 0.33, blue: 0.247)

    private enum DeckPage: Hashable {
        case cover, read, moments, slide(Int), plan, odds, impact, next
    }

    private var pages: [DeckPage] {
        var out: [DeckPage] = [.cover]
        if !deck.interests.isEmpty { out.append(.read) }
        if !deck.keyMoments.isEmpty { out.append(.moments) }
        for index in 0..<deck.slides.count { out.append(.slide(index)) }
        if !deck.closePlan.isEmpty { out.append(.plan) }
        out.append(.odds)
        if !deck.impactMoments.isEmpty { out.append(.impact) }
        if !deck.nextSteps.isEmpty { out.append(.next) }
        return out
    }

    private var stampText: String? {
        if deck.sample == true { return "SAMPLE" }
        if deck.draft == true { return "DRAFT" }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                // Jasper peeking from BEHIND the notebook — drawn FIRST so the
                // paper covers his body and only his head shows over the edge.
                WhisperEmberMascot(size: 56, isActive: true, coachMode: WhisperEmberCoachMode.load())
                    .offset(x: 26, y: 0)
                    .allowsHitTesting(false)

                book
                    .padding(.top, 30)
            }
            pager
        }
        .onChange(of: page) { _, _ in Haptics.tap() }
    }

    // MARK: - The book

    /// A small stack of pages with the ruled sheet on top — pages swipe while
    /// the stack (and Jasper) stay put.
    private var book: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(paperEdge)
                .rotationEffect(.degrees(-1.1))
                .offset(x: -3, y: 5)
            RoundedRectangle(cornerRadius: 18)
                .fill(paperEdge2)
                .rotationEffect(.degrees(0.8))
                .offset(x: 4, y: 7)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, deckPage in
                    paperPage(deckPage)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .frame(height: 470)
        .shadow(color: .black.opacity(0.26), radius: 16, y: 9)
    }

    private var pager: some View {
        HStack(spacing: 10) {
            pagerChip(icon: "chevron.left", disabled: page == 0) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    page = max(0, page - 1)
                }
            }
            .accessibilityLabel("Previous page")

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? mintDeep : Color.primary.opacity(0.22))
                        .frame(width: index == page ? 18 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: page)

            Spacer(minLength: 4)

            pagerChip(icon: "chevron.right", disabled: page >= pages.count - 1) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    page = min(pages.count - 1, page + 1)
                }
            }
            .accessibilityLabel("Next page")
        }
    }

    /// Cream paper chip — readable on dark cards and light sheets alike.
    private func pagerChip(icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: 36, height: 36)
                .background(paper, in: Circle())
                .overlay { Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1) }
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    // MARK: - The paper page

    private func paperPage(_ deckPage: DeckPage) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18).fill(paper)
            Canvas { context, size in
                var y: CGFloat = 58
                while y < size.height - 14 {
                    var path = Path()
                    path.move(to: CGPoint(x: 12, y: y))
                    path.addLine(to: CGPoint(x: size.width - 12, y: y))
                    context.stroke(path, with: .color(paperLine), lineWidth: 1)
                    y += 26
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            Rectangle()
                .fill(marginRed.opacity(0.7))
                .frame(width: 1)
                .padding(.leading, 38)
                .padding(.vertical, 10)

            ScrollView(showsIndicators: false) {
                pageContent(deckPage)
                    .padding(.leading, 52)
                    .padding(.trailing, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let stampText {
                Text(stampText)
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color(red: 0.75, green: 0.22, blue: 0.17).opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(red: 0.75, green: 0.22, blue: 0.17).opacity(0.6), lineWidth: 2)
                    }
                    .rotationEffect(.degrees(-8))
                    .padding(.top, 18)
                    .padding(.trailing, 18)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(page + 1) / \(pages.count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(inkSoft.opacity(0.8))
                .padding(.trailing, 14)
                .padding(.bottom, 9)
        }
    }

    // MARK: - Shared page pieces

    private func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black))
            .tracking(2.2)
            .foregroundStyle(mintDeep)
    }

    private func serifTitle(_ text: String, size: CGFloat = 24) -> some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .serif))
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func highlighted(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint, in: RoundedRectangle(cornerRadius: 4))
            .rotationEffect(.degrees(-0.35), anchor: .leading)
    }

    private func momentTint(_ kind: String) -> (fill: Color, label: String, labelColor: Color) {
        switch kind {
        case "objection": return (hiAmber, "OBJECTION", Color(red: 0.541, green: 0.416, blue: 0.071))
        case "signal": return (hiMint, "BUYING SIGNAL", Color(red: 0.043, green: 0.478, blue: 0.357))
        default: return (hiRose, "INTEREST", Color(red: 0.627, green: 0.322, blue: 0.275))
        }
    }

    // MARK: - Page content

    @ViewBuilder
    private func pageContent(_ deckPage: DeckPage) -> some View {
        switch deckPage {
        case .cover: coverPage
        case .read: readPage
        case .moments: momentsPage
        case .slide(let index): slidePage(index)
        case .plan: planPage
        case .odds: oddsPage
        case .impact: impactPage
        case .next: nextPage
        }
    }

    private var coverPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("Jasper's pitch deck")
            Text(deck.prospectName)
                .font(.system(size: 34, weight: .black, design: .serif))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text("\(deck.meetingTitle) · \(deck.generatedDate.formatted(date: .long, time: .omitted))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(inkSoft)
                .padding(.top, 6)
            HStack(spacing: 5) {
                Image(systemName: "scope")
                    .font(.system(size: 10, weight: .bold))
                Text(deck.placementLabel.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.8)
            }
            .foregroundStyle(mintDeep)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(mintDeep.opacity(0.1), in: Capsule())
            .overlay { Capsule().strokeBorder(mintDeep.opacity(0.25), lineWidth: 1) }
            .padding(.top, 12)

            Text("THE ANGLE")
                .font(.system(size: 10, weight: .black))
                .tracking(1.6)
                .foregroundStyle(inkSoft)
                .padding(.top, 28)
            highlighted(deck.headline, tint: hiMint)
                .padding(.top, 8)
            Text("Drafted by Jasper from what was actually said in the meeting — flip through for the read, the plan, and your close odds.")
                .font(.system(size: 11.5))
                .foregroundStyle(inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }

    private var readPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("The read")
            serifTitle("What \(deck.prospectName.components(separatedBy: " ").first ?? deck.prospectName) actually cares about")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(deck.interests.enumerated()), id: \.offset) { index, interest in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(mintDeep, in: Circle())
                        if index == 0 {
                            highlighted(interest, tint: hiMint)
                        } else {
                            Text(interest)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 16)
            Text("Pitch to these — in their words, not yours. The first one is the door.")
                .font(.system(size: 11))
                .foregroundStyle(inkSoft)
                .padding(.top, 18)
        }
    }

    private var momentsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("Key moments")
            serifTitle("Highlighted from the call")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(deck.keyMoments.prefix(4).enumerated()), id: \.offset) { _, moment in
                    let tint = momentTint(moment.kind)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(tint.label)
                                .font(.system(size: 8.5, weight: .black))
                                .tracking(0.7)
                                .foregroundStyle(tint.labelColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(tint.fill, in: RoundedRectangle(cornerRadius: 4))
                            Text("@\(moment.speaker)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(inkSoft)
                        }
                        highlighted("\u{201C}\(moment.quote)\u{201D}", tint: tint.fill)
                        if !moment.note.isEmpty {
                            Text("\u{21B3} \(moment.note)")
                                .font(.system(size: 11, weight: .medium))
                                .italic()
                                .foregroundStyle(inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    private func slidePage(_ index: Int) -> some View {
        let slide = deck.slides[min(index, deck.slides.count - 1)]
        return VStack(alignment: .leading, spacing: 0) {
            kicker("The play · \(index + 1) of \(deck.slides.count)")
            serifTitle(slide.title)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(slide.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(mintDeep)
                            .padding(.top, 2)
                        Text(bullet)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    private var planPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("The close plan")
            serifTitle("Run it in this order")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(deck.closePlan.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(paper)
                            .frame(width: 22, height: 22)
                            .background(ink, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.step)
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if !step.detail.isEmpty {
                                Text(step.detail)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    private func rateRow(label: String, value: Int, tint: Color, bigNumber: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                (Text("\(value)")
                    .font(.system(size: bigNumber, weight: .black, design: .serif))
                 + Text("%")
                    .font(.system(size: bigNumber * 0.38, weight: .black, design: .serif)))
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 0.91, green: 0.878, blue: 0.796))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(8, geo.size.width * CGFloat(value) / 100))
                }
            }
            .frame(height: 10)
        }
    }

    private var oddsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("Close probability")
            serifTitle("The honest odds")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 20) {
                rateRow(label: "If the plan is followed", value: deck.closeRate.withPlan, tint: mintDeep, bigNumber: 40)
                rateRow(label: "If it's winged", value: deck.closeRate.withoutPlan, tint: roseDeep, bigNumber: 30)
                HStack(spacing: 5) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11, weight: .bold))
                    Text("+\(max(0, deck.closeRate.withPlan - deck.closeRate.withoutPlan)) points for running the plan")
                        .font(.system(size: 11.5, weight: .black))
                }
                .foregroundStyle(mintDeep)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(mintDeep.opacity(0.08), in: Capsule())
                .overlay { Capsule().strokeBorder(mintDeep.opacity(0.2), lineWidth: 1) }
            }
            .padding(.top, 18)
            if !deck.closeRate.why.isEmpty {
                Text("\u{201C}\(deck.closeRate.why)\u{201D}")
                    .font(.system(size: 12, weight: .medium))
                    .italic()
                    .foregroundStyle(inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }
        }
    }

    private var impactPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("Your highest impact")
            serifTitle("The moments you landed")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(deck.impactMoments.prefix(3).enumerated()), id: \.offset) { index, impact in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 0.851, green: 0.482, blue: 0.184))
                            Text("IMPACT \(index + 1)")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.2)
                                .foregroundStyle(Color(red: 0.851, green: 0.482, blue: 0.184))
                        }
                        highlighted("\u{201C}\(impact.quote)\u{201D}", tint: hiMint)
                        if !impact.why.isEmpty {
                            Text("\u{21B3} \(impact.why)")
                                .font(.system(size: 11, weight: .medium))
                                .italic()
                                .foregroundStyle(inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 16)
            Text("Say these again in the follow-up — they already worked once.")
                .font(.system(size: 11))
                .foregroundStyle(inkSoft)
                .padding(.top, 18)
        }
    }

    private var nextPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker("Next steps")
            serifTitle("Before the trail goes cold")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 13) {
                ForEach(Array(deck.nextSteps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(mintDeep)
                            .padding(.top, 1)
                        Text(step.action)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(step.when)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(mintDeep)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(mintDeep.opacity(0.09), in: Capsule())
                    }
                }
            }
            .padding(.top, 16)
            Text(deck.sample == true
                 ? "Jasper drafted this from the live conversation — double-check anything before you promise it. This one is a sample so you can see the formatting."
                 : "Jasper drafted this from the live conversation — double-check anything before you promise it.")
                .font(.system(size: 10.5))
                .foregroundStyle(inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
        }
    }
}
