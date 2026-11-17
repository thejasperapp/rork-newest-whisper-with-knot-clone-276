import Foundation
import Observation

@MainActor @Observable
final class RecruiterTeamViewModel {
    nonisolated struct Team: Decodable, Identifiable, Sendable { let id: String; let name: String }
    nonisolated struct Teams: Decodable, Sendable { let teams: [Team] }
    nonisolated struct Cards: Decodable, Sendable { let cards: [RecruiterTeamCard]; let revisions: [String: Int] }
    let owner: String = AccountStorage.currentUserID.lowercased()
    private let generation: UUID = AccountStorage.generation
    var teams: [Team] = []
    var cards: [RecruiterTeamCard] = []
    var revisions: [String: Int] = [:]
    var business: String = ""
    var update: String = ""
    var reviewed: Bool = false
    var isBusy: Bool = false
    var hasVerified: Bool = false
    var errorText: String?
    var isCurrent: Bool { generation == AccountStorage.generation && owner == AccountStorage.currentUserID.lowercased() && AuthenticationService.shared.isSignedIn }
    func loadTeams() async {
        do {
            let result: Teams = try await JasperMeetingService.request("clients/teams", owner: owner)
            guard isCurrent else { return }
            teams = result.teams; errorText = nil
        } catch { if isCurrent { teams = []; cards = []; errorText = error.localizedDescription } }
    }
    func loadCards() async {
        let id = business
        guard !id.isEmpty, !isBusy, isCurrent else { return }
        do {
            let result: Cards = try await JasperMeetingService.request("clients/team?businessId=\(id)", owner: owner)
            guard isCurrent, business == id else { return }
            if revisions != result.revisions { reviewed = false }
            revisions = result.revisions; cards = result.cards; hasVerified = true; errorText = nil
        } catch { if isCurrent, business == id { cards = []; hasVerified = false; errorText = error.localizedDescription } }
    }
    func publish(_ prospect: WhisperRecruiterService.ProspectRow, revoke: Bool) async {
        guard isCurrent, !isBusy, !business.isEmpty, revoke || (reviewed && hasVerified) else { return }
        isBusy = true; errorText = nil
        let id = business
        let previous = cards.first { $0.id == prospect.id && $0.publisherId == owner }
        var body: [String: Any] = ["id": prospect.id, "confirm": true]
        if revoke { body["action"] = "revoke" }
        else {
            body["revision"] = revisions[prospect.id] ?? previous?.revision ?? 0
            body["name"] = prospect.prospect_display_name ?? prospect.prospect_username ?? "Unnamed"
            body["role"] = prospect.suggested_role ?? "unspecified"
            body["stage"] = prospect.status
            body["update"] = update
        }
        do {
            if revoke { let _: [String: Bool] = try await JasperMeetingService.request("clients/team?businessId=\(id)", owner: owner, body: body) }
            else { let _: RecruiterTeamCard = try await JasperMeetingService.request("clients/team?businessId=\(id)", owner: owner, body: body) }
            reviewed = false; isBusy = false
            await loadCards()
        } catch { isBusy = false; if isCurrent { errorText = error.localizedDescription } }
    }
}
