import Foundation
import Observation

@MainActor @Observable final class WorkspaceWorkViewModel {
    let owner: String = AccountStorage.currentUserID.lowercased()
    private let generation: UUID = AccountStorage.generation
    var space: String = AccountStorage.currentUserID.lowercased()
    var team: Bool = false
    var board: WorkspaceWorkItem.Board?
    var people: [WorkspaceWorkItem.Person] = []
    var teams: [WorkspaceWorkItem.Team] = []
    var intake: WorkspaceWorkItem.Intake?
    var item: WorkspaceWorkItem?
    var draft: WorkspaceWorkDraft?
    var errorText: String?
    var isLoading: Bool = false
    var filter: String = "active"
    var kind: String = "all"
    var search: String = ""
    var path: [String] = []
    private var epoch: Int = 0
    private var itemRequest: UUID = UUID()
    var isCurrent: Bool { owner == AccountStorage.currentUserID.lowercased() && generation == AccountStorage.generation }
    var visibleItems: [WorkspaceWorkItem.Summary] {
        (board?.items ?? []).filter { item in
            (kind == "all" || item.kind == kind) && (search.isEmpty || item.title.localizedStandardContains(search)) && (filter == "all" || (filter == "attention" ? item.needsAttention : filter == "mine" ? item.assigneeId == owner && item.status != "archived" : item.status != "archived"))
        }.sorted { if $0.needsAttention != $1.needsAttention { return $0.needsAttention }; return $0.updatedAt > $1.updatedAt }
    }
    func route(_ suffix: String = "") -> String { "workspace\(suffix)?space=\(space)&team=\(team ? "1" : "0")" }
    func link(_ id: String? = nil) -> URL? {
        var url = URLComponents(string: "https://mydailywhisper.com/work")
        url?.queryItems = [URLQueryItem(name: "portal", value: "workspace"), URLQueryItem(name: "space", value: space), URLQueryItem(name: "team", value: team ? "1" : "0")]
        if let id { url?.queryItems?.append(URLQueryItem(name: "id", value: id)) }
        return url?.url
    }
    func select(space: String, team: Bool) async {
        epoch += 1; self.space = space; self.team = team; board = nil; item = nil; intake = nil; people = []; draft = nil; path = []; isLoading = false; kind = "all"; filter = "active"; search = ""
        await load()
    }
    func openLink(_ text: String) async {
        guard let url = URLComponents(string: text), url.path == "/work", let selected = url.queryItems?.first(where: { $0.name == "space" })?.value, UUID(uuidString: selected) != nil else { errorText = "Paste a Whisper workspace link."; return }
        await select(space: selected.lowercased(), team: url.queryItems?.first(where: { $0.name == "team" })?.value == "1")
        if board != nil, let id = url.queryItems?.first(where: { $0.name == "id" })?.value, UUID(uuidString: id) != nil { path = [id.lowercased()] }
    }
    func load() async {
        guard isCurrent, !isLoading else { return }; let version = epoch
        isLoading = true; defer { if version == epoch { isLoading = false } }
        do {
            let result: WorkspaceWorkItem.Board = try await JasperMeetingService.request(route(), owner: owner)
            guard isCurrent, version == epoch else { return }
            if board?.member != result.member || board?.canSubmit != result.canSubmit || board?.owner != result.owner { item = nil; draft = nil; intake = nil; people = []; kind = "all" }
            board = result; errorText = nil
            if result.member {
                struct People: Decodable { let people: [WorkspaceWorkItem.Person] }
                let members: People = try await JasperMeetingService.request(route("/members"), owner: owner)
                guard isCurrent, version == epoch else { return }; people = members.people
            }
        } catch { if isCurrent, version == epoch { errorText = error.localizedDescription; board = nil; item = nil; intake = nil; people = []; draft = nil; itemRequest = UUID() } }
    }
    func loadTeams() async {
        do { struct Teams: Decodable { let teams: [WorkspaceWorkItem.Team] }; let result: Teams = try await JasperMeetingService.request("clients/teams", owner: owner); if isCurrent { teams = result.teams } }
        catch { if isCurrent { errorText = error.localizedDescription } }
    }
    func loadItem(_ id: String) async {
        guard isCurrent, UUID(uuidString: id) != nil else { return }; let version = epoch; let request = UUID(); itemRequest = request
        do {
            let result: WorkspaceWorkItem = try await JasperMeetingService.request(route("/item/\(id)"), owner: owner)
            guard isCurrent, version == epoch, itemRequest == request else { return }
            if item?.external != result.external || item?.canManage != result.canManage || item?.canDecide != result.canDecide { draft = nil }
            item = result; errorText = nil
        } catch { if isCurrent, version == epoch, itemRequest == request { item = nil; draft = nil; errorText = error.localizedDescription } }
    }
    func loadIntake() async {
        guard isCurrent else { return }; let version = epoch
        do { let result: WorkspaceWorkItem.Intake = try await JasperMeetingService.request(route("/intake"), owner: owner); if isCurrent, version == epoch { intake = result } }
        catch { if isCurrent, version == epoch { intake = nil; draft = nil; errorText = error.localizedDescription } }
    }
    func save(_ draft: WorkspaceWorkDraft) async {
        guard isCurrent, draft.canSave else { return }; let version = epoch; let destination = route(draft.suffix)
        draft.isSaving = true; defer { draft.isSaving = false }
        do {
            struct Acknowledged: Decodable {}
            let _: Acknowledged = try await JasperMeetingService.request(destination, owner: owner, body: draft.body())
            guard isCurrent, version == epoch else { return }; self.draft = nil; errorText = nil
            if !draft.suffix.isEmpty { await loadIntake() }
            if let id = path.last { await loadItem(id) }
            await load()
        } catch {
            if isCurrent, version == epoch {
                draft.approved = false
                if let failure = error as? JasperMeetingFailure, ["workspace_access_denied", "sign_in_required"].contains(failure.code) {
                    clear(); errorText = error.localizedDescription
                } else { draft.errorText = error.localizedDescription }
            }
        }
    }
    func name(_ id: String) -> String { people.first { $0.id == id }?.username ?? (id == owner ? "You" : "Account \(id.prefix(8))") }
    func clear() { epoch += 1; board = nil; item = nil; people = []; teams = []; intake = nil; draft = nil; path = [] }
}
