import SwiftUI
import UIKit

/// Native iOS pitch deck — rebuilt in Whisper components instead of a web view
/// so recruiters can present from their phone with smooth scrolling, native
/// cards, and a layout that fits the iPhone screen.
struct WhisperNativePitchDeckView: View {
    @Environment(\.colorScheme) private var colorScheme
    let audience: WhisperPitchAudience

    @State private var expandedFAQ: Set<Int> = []
    @State private var showPresenterNotes: Bool = false
    @State private var showCopied: Bool = false

    private var content: WhisperPitchDeckContent {
        pitchContent(for: audience)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                beforeAfterSection
                ForEach(content.sections.indices, id: \.self) { i in
                    sectionCard(content.sections[i])
                }
                previewCardsSection
                faqSection
                presenterNotesToggle
                if showPresenterNotes {
                    secretsSection
                }
                ctaSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(WhisperTheme.surface(colorScheme))
        .overlay(alignment: .top) {
            if showCopied {
                copiedToast
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(audience.accent.opacity(colorScheme == .dark ? 0.18 : 0.10))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: audience.icon)
                        .font(.caption.weight(.bold))
                    Text(content.hero.eyebrow)
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                }
                .foregroundStyle(audience.accent)

                Text(content.hero.title)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .multilineTextAlignment(.leading)

                Text(content.hero.lead)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(20)
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(audience.accent.opacity(0.25), lineWidth: 1)
        }
    }

    // MARK: - Before / After

    private var beforeAfterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before → After")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .tracking(0.5)

            VStack(spacing: 10) {
                ForEach(content.beforeAfter.indices, id: \.self) { i in
                    let pair = content.beforeAfter[i]
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Before")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Text(pair.before)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .strikethrough()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(audience.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("After")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(audience.accent)
                            Text(pair.after)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private func sectionCard(_ section: WhisperPitchSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(audience.accent)
                .tracking(0.5)

            Text(section.title)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(WhisperTheme.ink(colorScheme))

            Text(section.lead)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))

            if !section.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.bullets.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(audience.accent)
                            Text(section.bullets[i])
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Interactive previews

    private var previewCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INTERACTIVE PREVIEW")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .tracking(0.5)

            WhisperPitchPreviewCards(audience: audience)
        }
    }

    // MARK: - FAQ

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FAQ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .tracking(0.5)

            VStack(spacing: 10) {
                ForEach(content.faq.indices, id: \.self) { i in
                    faqAccordion(i)
                }
            }
        }
    }

    private func faqAccordion(_ i: Int) -> some View {
        let item = content.faq[i]
        let isExpanded = expandedFAQ.contains(i)
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.28)) {
                if isExpanded {
                    expandedFAQ.remove(i)
                } else {
                    expandedFAQ.insert(i)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(item.question)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(12)

                if isExpanded {
                    Text(item.answer)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Presenter notes

    private var presenterNotesToggle: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.28)) {
                showPresenterNotes.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: showPresenterNotes ? "eye.slash.fill" : "eye.fill")
                    .font(.caption.weight(.bold))
                Text(showPresenterNotes ? "Hide presenter notes" : "Show presenter notes")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Image(systemName: showPresenterNotes ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secrets / Speaker notes

    private var secretsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presenter Notes")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .tracking(0.5)

            VStack(spacing: 10) {
                ForEach(content.secrets.indices, id: \.self) { i in
                    let secret = content.secrets[i]
                    VStack(alignment: .leading, spacing: 3) {
                        Text(secret.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(audience.accent)
                        Text(secret.content)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(audience.accent.opacity(0.08), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(audience.accent.opacity(0.18), lineWidth: 1)
                    }
                }
            }
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 10) {
            if let url = content.cta.url {
                Link(destination: url) {
                    Text(content.cta.title)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
            } else {
                Text(content.cta.title)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }

            Button {
                Haptics.tap()
                if let url = content.cta.url {
                    UIPasteboard.general.url = url
                    UIPasteboard.general.string = "Check out the Whisper pitch for \(audience.title): \(url.absoluteString)"
                }
                withAnimation(.spring(response: 0.28)) {
                    showCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.spring(response: 0.28)) {
                        showCopied = false
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("Copy pitch link")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Text("Every demo uses real product screens with clearly marked sample data.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var copiedToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
            Text("Copied")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.15), in: Capsule())
        .padding(.top, 12)
    }
}

// MARK: - Data model

private struct WhisperPitchDeckContent {
    let hero: (eyebrow: String, title: String, lead: String)
    let beforeAfter: [(before: String, after: String)]
    let sections: [WhisperPitchSection]
    let faq: [(question: String, answer: String)]
    let secrets: [(label: String, content: String)]
    let cta: (title: String, url: URL?)
}

private struct WhisperPitchSection {
    let eyebrow: String
    let title: String
    let lead: String
    let bullets: [String]
}

// MARK: - Content per audience

private func pitchContent(for audience: WhisperPitchAudience) -> WhisperPitchDeckContent {
    switch audience.id {
    case "brands":
        return brandPitchContent
    case "creators":
        return creatorPitchContent
    case "athletes":
        return athletePitchContent
    case "coaches":
        return coachPitchContent
    case "recruiters":
        return recruiterPitchContent
    default:
        return brandPitchContent
    }
}

private let brandPitchContent = WhisperPitchDeckContent(
    hero: (
        eyebrow: "For Brands",
        title: "Sponsor the right creators — escrowed, tracked, automatic",
        lead: "Post a sponsorship, see creators apply, accept or counter, fund escrow, and watch tracked posts release payment — all in one dashboard."
    ),
    beforeAfter: [
        ("DMs and email chains to find creators", "Public directory with pay range on the card"),
        ("Chasing creators for proof of posts", "Tracked posts prove reach automatically"),
        ("Net-30 invoices and payment risk", "Escrow funded up front, released on verified posts"),
        ("Manual contract negotiation", "Accept / counter / deny in one screen")
    ],
    sections: [
        WhisperPitchSection(
            eyebrow: "The brand dashboard",
            title: "One screen for every sponsorship",
            lead: "Switch between sample brands to see how applications, deals, and escrow payments scale. Every interaction is live.",
            bullets: ["Accept, counter, or deny creator applications", "Fund escrow directly from the deal card", "Dispute unresolved releases with one tap"]
        ),
        WhisperPitchSection(
            eyebrow: "How creators find you",
            title: "Your brand profile is your storefront",
            lead: "Publish your brand and creators see pay range on the card — no DM negotiation in the dark.",
            bullets: ["Full profile with requirements and perks", "Jasper verification check builds trust", "Apply flow takes under a minute"]
        ),
        WhisperPitchSection(
            eyebrow: "Trust layer",
            title: "Only verified brands can sponsor",
            lead: "Jasper confirms the company, product line, and payout history before a brand profile goes live.",
            bullets: ["Company + product verification", "Payout history score out of 100", "Fraudulent brands cannot fund escrow"]
        )
    ],
    faq: [
        ("How do we know posts actually went live?", "Creators link their Whisper post to the deal. Whisper verifies the post is live and reads likes + comments back into the deal card. Escrow only releases after verification."),
        ("What if a creator doesn't deliver?", "You can dispute any pending escrow payment. Funds are held until the dispute is resolved, and undelivered posts don't release."),
        ("How does Jasper verify a brand?", "We confirm the company, product line, and creator payout history. A score out of 100 is published on the brand profile.")
    ],
    secrets: [
        ("Pricing", "10% platform fee on released payments. No listing, no subscription, no ad minimums."),
        ("Roadmap", "Q4: self-serve brand onboarding, automated contract PDFs, and Shopify integration for product seeding."),
        ("Edge case", "If a creator disputes a release, both parties get a DM thread and a 7-day mediation window before auto-refund.")
    ],
    cta: (title: "Open brand pitch on the web", url: URL(string: "\(WhisperBillingBackend.webOrigin)/pitch/brands"))
)

private let creatorPitchContent = WhisperPitchDeckContent(
    hero: (
        eyebrow: "For Creators",
        title: "Get paid for the content you already make",
        lead: "Brand marketplace, sample sponsorship deals, and the WPP ad-revenue program — all from your profile."
    ),
    beforeAfter: [
        ("Cold DM brands and hope for a reply", "Apply to vetted brands with pay range visible"),
        ("Chase invoices 30–90 days later", "Money held in escrow before you post"),
        ("Algorithm-dependent ad revenue", "Transparent WPP payout per 1k qualified views"),
        ("No proof of deliverables", "Tracked posts release payment automatically")
    ],
    sections: [
        WhisperPitchSection(
            eyebrow: "Brand marketplace",
            title: "Apply to verified deals in two taps",
            lead: "Browse brands, see requirements and pay range, then apply with a short note. No DMs required.",
            bullets: ["Verified brands only", "Pay range printed on the card", "Accept, counter, or pass on any offer"]
        ),
        WhisperPitchSection(
            eyebrow: "WPP program",
            title: "Earn per qualified view",
            lead: "WPP pays creators monthly based on eligible Reels and thread views. No sponsorship required.",
            bullets: ["Opens at 1,000 followers", "Tiered RPM based on engagement", "Paid monthly via Stripe"]
        ),
        WhisperPitchSection(
            eyebrow: "Earnings",
            title: "Escrow protects every deal",
            lead: "Brands fund escrow before you post. Tracked posts prove delivery and release payment automatically.",
            bullets: ["Per-post and weekly deals", "Automatic verification", "Dispute protection built in"]
        )
    ],
    faq: [
        ("When do I get paid?", "Per-post deals release when your tracked post goes live. Monthly deals release at the end of the week once your posts are verified."),
        ("Can I negotiate terms?", "Yes. When you apply, the brand can accept, counter with new terms, or pass. You see the counter in My Sponsorships."),
        ("What counts as a qualified WPP view?", "Views on Reels and threads that meet the partner tier's eligibility rules: real account, minimum watch time, no repeated loops.")
    ],
    secrets: [
        ("Eligibility", "WPP opens at 1,000 followers. Brand marketplace has no follower minimum, but each brand sets their own requirements."),
        ("Payouts", "WPP is paid monthly via Stripe. Sponsorships are paid per-release or per-week depending on the deal basis."),
        ("Growth", "Featured creators get priority brand marketplace placement and recruiter introductions.")
    ],
    cta: (title: "Open creator pitch on the web", url: URL(string: "\(WhisperBillingBackend.webOrigin)/pitch/creators"))
)

private let athletePitchContent = WhisperPitchDeckContent(
    hero: (
        eyebrow: "For Athletes",
        title: "Turn your training into sponsorships",
        lead: "Athletes get discovered, featured, and sponsored — plus WPP earnings on top of every post."
    ),
    beforeAfter: [
        ("Agents and cold emails", "Verified athlete badge + public profile"),
        ("Unclear NIL rules", "Built-in escrow, tracked posts, compliant deals"),
        ("Inconsistent sponsorship income", "Brand marketplace + WPP revenue stack"),
        ("No central place to be found", "Recruiters browse athlete profiles directly")
    ],
    sections: [
        WhisperPitchSection(
            eyebrow: "Athlete profile",
            title: "Your sports résumé, public and searchable",
            lead: "Verified athletes get a badge and a dedicated profile that brands and recruiters can browse.",
            bullets: ["Verified athlete badge", "Sport, stats, and achievements", "Sponsorship and booking links"]
        ),
        WhisperPitchSection(
            eyebrow: "Brand deals",
            title: "NIL-ready sponsorships",
            lead: "Apply to brand deals built with athlete compliance in mind. Escrow and tracked posts keep everyone protected.",
            bullets: ["Compliant deal terms", "Escrow-funded before posting", "Tracked deliverables"]
        ),
        WhisperPitchSection(
            eyebrow: "Recruiter access",
            title: "Get discovered by recruiters",
            lead: "Approved recruiters can view athlete profiles, request meetings, and promote prospects to verified status.",
            bullets: ["Public recruiter directory", "One-tap meeting requests", "Promotion to verified athlete"]
        )
    ],
    faq: [
        ("Is this only for college athletes?", "No — any athlete with a verified profile can use the marketplace and WPP. College athletes get NIL-compliant deal language by default."),
        ("How do I get verified?", "Apply for the athlete badge. We verify your sport, affiliation, and identity before the badge appears on your profile."),
        ("Can I also earn WPP?", "Yes. Athlete posts are eligible for WPP just like creator posts once you hit the follower threshold.")
    ],
    secrets: [
        ("Eligibility", "Athlete badge is an annual subscription. Verification includes sport, school/team, and identity check."),
        ("NIL", "Deal terms default to compliant language. Schools and collectives can request admin access."),
        ("Recruiter bounties", "Recruiters earn a bounty when they promote an athlete who activates a badge.")
    ],
    cta: (title: "Open athlete pitch on the web", url: URL(string: "\(WhisperBillingBackend.webOrigin)/pitch/athletes"))
)

private let coachPitchContent = WhisperPitchDeckContent(
    hero: (
        eyebrow: "For Coaches",
        title: "A real coaching business, built in",
        lead: "Set your rate, clients subscribe, Stripe pays you out — and you run check-ins, programs, and macros right in DMs."
    ),
    beforeAfter: [
        ("Payments through Venmo or cash apps", "Stripe subscription, automatic payouts"),
        ("Spreadsheets for programs", "Built-in program builder and delivery"),
        ("Manual check-in reminders", "DM-based check-ins with macro tracking"),
        ("No discoverability", "Hire button on your public profile")
    ],
    sections: [
        WhisperPitchSection(
            eyebrow: "Money flow",
            title: "Subscriptions that pay themselves",
            lead: "Clients subscribe through your profile link. Stripe handles billing and pays your bank account.",
            bullets: ["Monthly or annual plans", "Coach sets the rate", "Payouts in 1–2 business days"]
        ),
        WhisperPitchSection(
            eyebrow: "Client tools",
            title: "Run your coaching in DMs",
            lead: "Send programs, log macros, and run check-ins without leaving the thread. Clients see everything in their inbox.",
            bullets: ["Program builder and delivery", "Macro and food logging", "Scheduled check-in messages"]
        ),
        WhisperPitchSection(
            eyebrow: "Beyond subscriptions",
            title: "Brand deals and WPP too",
            lead: "Coaches with an audience can apply to brand deals and earn WPP on their content alongside subscriptions.",
            bullets: ["Brand marketplace access", "WPP revenue on Reels and threads", "Multiple income streams in one profile"]
        )
    ],
    faq: [
        ("Do clients subscribe through Whisper or my own site?", "Either. Every coach gets a shareable link and a Hire button on their profile. Clients subscribe in-app."),
        ("How long until payouts hit my bank?", "Stripe processes payouts automatically. Most coaches see the money in their bank account within 1–2 business days of release."),
        ("Can I also take sponsorships?", "Yes. Coaches with an audience can apply to brand deals from the same marketplace and earn WPP on their content.")
    ],
    secrets: [
        ("Stripe", "Stripe Connect Express onboarding; Whisper never holds coach funds."),
        ("Platform fee", "10% on client payments. No other fees for coaches."),
        ("Churn", "Monthly subscriptions recur automatically. Failed payments retry 3 times before pausing.")
    ],
    cta: (title: "Open coach pitch on the web", url: URL(string: "\(WhisperBillingBackend.webOrigin)/pitch/coaches"))
)

private let recruiterPitchContent = WhisperPitchDeckContent(
    hero: (
        eyebrow: "For Recruiters",
        title: "Scout, track, and promote talent",
        lead: "A live, clickable pipeline with sample talent, meeting requests, and one-tap promotions."
    ),
    beforeAfter: [
        ("Notes in six different apps", "One pipeline with stages and counts"),
        ("Back-and-forth scheduling", "Public card with Schedule a call button"),
        ("Manual promotion requests", "One-tap promote to verified / coach / athlete"),
        ("No credit for referrals", "Tracked referral link and signup counter")
    ],
    sections: [
        WhisperPitchSection(
            eyebrow: "Pipeline",
            title: "Track prospects from discovery to promotion",
            lead: "Add prospects, move them through stages, and promote the ready ones. The funnel updates live.",
            bullets: ["Discovered → Contacted → Interested → Meeting → Ready → Promoted", "Notes and status per prospect", "Stage history for every lead"]
        ),
        WhisperPitchSection(
            eyebrow: "Meetings",
            title: "Approve or decline requests in one tap",
            lead: "Your featured public card has a Schedule a call button. Requests arrive with email, preferred time, and message.",
            bullets: ["Branded meeting invite flow", "Approve with a calendar link", "Decline with a polite note"]
        ),
        WhisperPitchSection(
            eyebrow: "Toolkit",
            title: "Referral link, territory, and targets",
            lead: "Share your code or link with prospects. Signups are credited server-side and show up in your dashboard.",
            bullets: ["Shareable signup link matches your profile invite", "Territory map and leaderboards", "Monthly targets and bounty tracking"]
        )
    ],
    faq: [
        ("How do prospects request a meeting?", "Your featured public card has a Schedule a call button. The request comes in with their email, preferred time, and a message — your calendar stays private."),
        ("Can I promote a user to verified?", "Yes. Ready prospects can be promoted to coach, athlete, or creator. Promotions are logged server-side and show on their profile."),
        ("How are signups credited to me?", "Your referral link adds a server-side tracking parameter. Every signup through that link is credited to your dashboard automatically.")
    ],
    secrets: [
        ("Compensation", "Recruiters earn per-promotion bounties and monthly bonuses against targets."),
        ("Territory", "Territory map is based on prospect location and source; admins can assign territories."),
        ("Automation", "Future: AI-suggested prospects based on public social profiles and engagement signals.")
    ],
    cta: (title: "Open recruiter pitch on the web", url: URL(string: "\(WhisperBillingBackend.webOrigin)/pitch/recruiters"))
)

