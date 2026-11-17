import Foundation
import Observation

@MainActor @Observable
final class RecruiterClientViewModel {
    let owner: String = AccountStorage.currentUserID.lowercased()
    private let generation: UUID = AccountStorage.generation
    var client: RecruiterClient = RecruiterClient()
    var isLoaded: Bool = false
    var isBusy: Bool = false
    var errorText: String?
    var notice: String?
    var answer: JasperMeetingAnswer?
    var approvedScope: String = ""
    var question: String = ""
    var operation: Task<Void, Never>?
    var isCurrent: Bool { generation == AccountStorage.generation && owner == AccountStorage.currentUserID.lowercased() && AuthenticationService.shared.isSignedIn }
    var scope: String { client.meetingIds.sorted().joined(separator: ",") }

    func load(id: String) async {
        guard !isBusy, isCurrent else { return }
        isBusy = true; errorText = nil
        defer { isBusy = false }
        do {
            let result: RecruiterClient = try await JasperMeetingService.request("clients/profile?id=\(id)", owner: owner)
            guard isCurrent else { return }
            client = result; isLoaded = true; approvedScope = ""; answer = nil
        } catch { if isCurrent { errorText = error.localizedDescription } }
    }
    func save(id: String) async {
        guard isLoaded, !isBusy, isCurrent else { return }
        isBusy = true; errorText = nil; notice = nil
        defer { isBusy = false }
        do {
            let data = try JSONEncoder().encode(client)
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let result: RecruiterClient = try await JasperMeetingService.request("clients/profile?id=\(id)", owner: owner, body: body)
            guard isCurrent else { return }
            client = result; notice = "Saved privately to your account."
            await WhisperRecruiterService.shared.refreshClientMetadata()
        } catch { if isCurrent { errorText = error.localizedDescription } }
    }
    func toggleMeeting(_ id: String) {
        guard !isBusy else { return }
        if client.meetingIds.contains(id) { client.meetingIds.removeAll { $0 == id } }
        else if client.meetingIds.count < 8 { client.meetingIds.append(id) }
        approvedScope = ""; operation?.cancel(); answer = nil
    }
    func ask(_ text: String, name: String) {
        guard !isBusy, !scope.isEmpty, scope == approvedScope, isCurrent else { return }
        let ids = client.meetingIds
        let frozenScope = scope
        isBusy = true; errorText = nil
        operation = Task {
            defer { isBusy = false }
            do {
                // Relationship answers stay meeting-grounded: no general-knowledge items can be mistaken for something the person said.
                let result: JasperMeetingAnswer = try await JasperMeetingService.request("ask", owner: owner, body: ["question": String("About \(name.prefix(140)): \(text)".prefix(600)), "meetingIds": ids, "mode": "ask", "knowledge": false, "consent": true])
                guard isCurrent, scope == frozenScope, approvedScope == frozenScope, !Task.isCancelled else { return }
                answer = result
            } catch { if isCurrent, !Task.isCancelled { errorText = error.localizedDescription } }
        }
    }
    func keepAnswer() async {
        guard !isBusy, let answer, let meeting = answer.sources.first?.meetingId else { return }
        isBusy = true; errorText = nil
        defer { isBusy = false }
        do {
            let _: [String: Bool] = try await JasperMeetingService.request("keep", owner: owner, body: ["id": answer.id, "meetingId": meeting])
            if isCurrent { notice = "Kept privately with the first cited meeting." }
        } catch { if isCurrent { errorText = error.localizedDescription } }
    }
}
