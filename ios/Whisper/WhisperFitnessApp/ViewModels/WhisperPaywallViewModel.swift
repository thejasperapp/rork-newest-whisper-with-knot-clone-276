import SwiftUI
import AuthenticationServices
import Supabase

/// Presentation and reconciliation for the existing hosted checkout. A browser
/// callback is never evidence of payment; access is read from the owner's row.
@MainActor
@Observable
final class WhisperPaywallViewModel {
    enum Offer { case one(WhisperOnePlan), badge(WhisperBadgeRole) }
    private(set) var isOpening: Bool = false
    private(set) var isChecking: Bool = false
    private(set) var isCheckoutOpen: Bool = false
    private(set) var hasAccess: Bool = false
    private(set) var didCheck: Bool = false
    private(set) var hasPendingCheckout: Bool = false
    @ObservationIgnored private var pendingCheckout: (offer: Offer, url: URL)?
    private(set) var notice: String?
    private(set) var errorMessage: String?
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private var presentationActive: Bool = true
    @ObservationIgnored private let owner: String = AccountStorage.currentUserID
    @ObservationIgnored private let generation: UUID = AccountStorage.generation

    var isBusy: Bool { isOpening || isChecking || isCheckoutOpen }
    private var isCurrent: Bool {
        presentationActive && generation == AccountStorage.generation && owner == AccountStorage.currentUserID
            && SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == owner.lowercased()
    }

    func refreshAccess(for offer: Offer, userInitiated: Bool = false) async {
        guard isCurrent, !isChecking else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        nonisolated struct Membership: Decodable { let status: String }
        do {
            let rows: [Membership]
            let client = SupabaseService.shared.client
            switch offer {
            case .one:
                rows = try await client.from("whisper_one_members").select("status")
                    .eq("user_id", value: owner).eq("status", value: "active").limit(1).execute().value
            case .badge(let role):
                rows = try await client.from("whisper_badge_members").select("status")
                    .eq("user_id", value: owner).eq("role", value: role.rawValue)
                    .eq("status", value: "active").limit(1).execute().value
            }
            guard isCurrent, !Task.isCancelled else { return }
            hasAccess = !rows.isEmpty
            didCheck = true
            if hasAccess {
                pendingCheckout = nil
                hasPendingCheckout = false
                notice = "Your access is active on this account."
                await WhisperUserService.shared.refreshMe()
                await WhisperOneService.shared.refreshCurrentMembership()
            } else if userInitiated {
                notice = "Active access hasn’t been confirmed yet. If you paid, allow a moment and refresh again before starting another checkout."
            }
        } catch {
            guard isCurrent else { return }
            errorMessage = "Your access couldn’t be checked. Please try again before purchasing."
        }
    }

    func open(_ offer: Offer) async {
        guard isCurrent, !isBusy, !hasAccess else { return }
        let checkoutOffer = pendingCheckout?.offer ?? offer
        await refreshAccess(for: checkoutOffer)
        guard isCurrent, !Task.isCancelled, didCheck, errorMessage == nil, !hasAccess else { return }
        isOpening = true
        errorMessage = nil
        notice = nil
        defer { isOpening = false }
        do {
            let url: URL
            if let pendingCheckout {
                url = pendingCheckout.url
            } else {
                switch checkoutOffer {
                case .one(let plan): url = try await WhisperBillingService.shared.startOneCheckout(plan: plan)
                case .badge(let role): url = try await WhisperBillingService.shared.startBadgeCheckout(role: role)
                }
            }
            guard isCurrent, !Task.isCancelled else { return }
            guard url.scheme == "https", let host = url.host, host == "checkout.stripe.com" || host.hasSuffix(".stripe.com") else {
                errorMessage = "Secure checkout couldn’t be opened. Please try again."
                return
            }
            pendingCheckout = (checkoutOffer, url)
            hasPendingCheckout = true
            let browser = ASWebAuthenticationSession(url: url, callbackURLScheme: "whisper") { [weak self] _, error in
                Task { @MainActor in
                    guard let self, self.isCurrent else { return }
                    self.isCheckoutOpen = false
                    self.session = nil
                    if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.errorMessage = "Checkout closed unexpectedly. Refresh access before trying again."
                    }
                    await self.refreshAccess(for: checkoutOffer, userInitiated: true)
                }
            }
            browser.presentationContextProvider = WebAuthPresenter.shared
            session = browser
            isCheckoutOpen = browser.start()
            if !isCheckoutOpen {
                session = nil
                errorMessage = "Checkout couldn’t open. Please try again."
            } else {
                notice = "When checkout is finished, return here and refresh access."
            }
        } catch {
            guard isCurrent else { return }
            errorMessage = (error as? WhisperBillingError)?.localizedDescription ?? "Checkout couldn’t be started. Check your connection and try again."
        }
    }

    func cancelPresentation() {
        presentationActive = false
        session?.cancel()
        session = nil
        isCheckoutOpen = false
    }
}
