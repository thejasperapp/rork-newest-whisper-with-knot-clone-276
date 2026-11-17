import SwiftUI
import AuthenticationServices

struct WhisperOnePaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPlan: WhisperOnePlan = .annual
    @State private var model: WhisperPaywallViewModel = WhisperPaywallViewModel()
    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var offer: WhisperPaywallViewModel.Offer { .one(selectedPlan) }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                WhisperMembershipIllustration(kind: .one)
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.hasAccess ? "A little more you.\nAlready yours." : "A little more room\nto be you.")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .tracking(-0.8).fixedSize(horizontal: false, vertical: true)
                    Text("Your voice, your progress, your people. Make more of your everyday with Whisper One.")
                        .font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 15) {
                    WhisperPaymentBenefit(symbol: "slider.horizontal.3", title: "Your tools, without a label", detail: "Membership stays separate from public identity.")
                    WhisperPaymentBenefit(symbol: "text.alignleft", title: "More room for your thoughts", detail: "Write posts up to 1,000 characters.")
                    WhisperPaymentBenefit(symbol: "person.2", title: "A start in coaching", detail: "Three client slots, programs and check-ins.")
                    WhisperPaymentBenefit(symbol: "chart.bar", title: "See your impact", detail: "Post reach and interaction analytics.")
                }
                if !model.hasAccess {
                    VStack(spacing: 10) {
                        planRow(.annual)
                        planRow(.monthly)
                    }
                    .disabled(model.isBusy || model.hasPendingCheckout)
                    Text("Prices in USD. \(selectedPlan.priceText) is billed \(selectedPlan == .annual ? "each year" : "each month"). Renews automatically until cancelled. Any applicable taxes are shown at checkout.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                status
                WhisperPaymentLegalFooter()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            WhisperPaymentHeader(title: "Whisper One", symbol: "plus") { model.cancelPresentation(); dismiss() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WhisperPaymentActionBar(
                title: model.hasAccess ? "You’re a member" : model.hasPendingCheckout ? "Resume secure checkout" : "Continue · \(selectedPlan.priceText)\(selectedPlan.intervalText)",
                isBusy: model.isOpening || model.isChecking,
                isDisabled: model.isBusy || model.hasAccess,
                refreshDisabled: model.isBusy,
                action: { Task { await model.open(offer) } },
                refresh: { Task { await model.refreshAccess(for: offer, userInitiated: true) } }
            )
        }
        .foregroundStyle(ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(WhisperMenuGeometry.sheetRadius)
        .task { await model.refreshAccess(for: offer) }
        .onDisappear { if !model.isCheckoutOpen { model.cancelPresentation() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            model.cancelPresentation(); dismiss()
        }
    }

    private func planRow(_ plan: WhisperOnePlan) -> some View {
        let selected = plan == selectedPlan
        return Button {
            Haptics.tap()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { selectedPlan = plan }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan == .annual ? "Yearly" : "Monthly").font(.headline)
                    Spacer(minLength: 8)
                    Text(plan.priceText).font(.title3.weight(.bold))
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3)
                }
                HStack(alignment: .top) {
                    Text(plan == .annual ? "One payment. A whole year." : "A little more, month by month.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if plan == .annual {
                        Text("SAVE 33%")
                            .font(.caption2.weight(.bold)).tracking(0.5)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .foregroundStyle(Color(red: 0.22, green: 0.20, blue: 0.19))
                            .background(Color(red: 1, green: 0.89, blue: 0.58), in: Capsule())
                    }
                }
            }
            .padding(18)
            .background(selected ? ink.opacity(0.045) : Color.clear, in: .rect(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(selected ? ink : WhisperTheme.hairline(colorScheme), lineWidth: selected ? 1.5 : 1) }
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(plan.displayName), \(plan.priceText) USD \(plan.intervalText)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var status: some View {
        if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
        if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
    }
}

struct WhisperBadgeActivateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let role: WhisperBadgeRole
    @State private var model: WhisperPaywallViewModel = WhisperPaywallViewModel()
    private var offer: WhisperPaywallViewModel.Offer { .badge(role) }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                WhisperMembershipIllustration(kind: role == .coach ? .coach : .badge)
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.hasAccess ? "Your next chapter\nis already here." : role == .coach ? "Good guidance.\nGreater possibility." : "Make your mark.\nBe unmistakably you.")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold)).tracking(-0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(role == .coach ? "Build a practice around the people you help. Your approved coaching tools, together on Whisper." : "Your approved role tools, with professional details on your profile.")
                        .font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 16) {
                    WhisperPaymentBenefit(symbol: "person.text.rectangle", title: "A clear professional profile", detail: "Your role as plain profile text, not a decorative seal or safety guarantee.")
                    if role == .coach {
                        WhisperPaymentBenefit(symbol: "person.2", title: "Room for every client", detail: "Unlimited clients with your verified coach plan.")
                        WhisperPaymentBenefit(symbol: "list.clipboard", title: "Your own coaching practice", detail: "Programs, check-ins and paid coaching tools.")
                    } else {
                        WhisperPaymentBenefit(symbol: "person.crop.circle", title: "Keep your original account", detail: "Your posts, people and conversations stay with you.")
                    }
                }
                if !model.hasAccess {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Annual activation").font(.headline)
                        Text("\(role.priceText) USD / year").font(.title2.bold())
                        Text("Application approval is required. Billed yearly and renews automatically until cancelled. Applicable taxes are shown at checkout.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 24, style: .continuous))
                }
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                WhisperPaymentLegalFooter()
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            WhisperPaymentHeader(title: role.displayName, symbol: "checkmark.seal") { model.cancelPresentation(); dismiss() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WhisperPaymentActionBar(
                title: model.hasAccess ? "Your access is active" : model.hasPendingCheckout ? "Resume secure checkout" : "Continue · \(role.priceText)/year",
                isBusy: model.isOpening || model.isChecking,
                isDisabled: model.isBusy || model.hasAccess,
                refreshDisabled: model.isBusy,
                action: { Task { await model.open(offer) } },
                refresh: { Task { await model.refreshAccess(for: offer, userInitiated: true) } }
            )
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .presentationDetents([.large]).presentationDragIndicator(.hidden)
        .presentationCornerRadius(WhisperMenuGeometry.sheetRadius)
        .task { await model.refreshAccess(for: offer) }
        .onDisappear { if !model.isCheckoutOpen { model.cancelPresentation() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            model.cancelPresentation(); dismiss()
        }
    }
}

@MainActor
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresenter()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else { return ASPresentationAnchor() }
        return window
    }
}
