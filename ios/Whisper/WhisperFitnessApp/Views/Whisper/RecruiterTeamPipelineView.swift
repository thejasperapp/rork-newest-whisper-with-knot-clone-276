import SwiftUI

struct RecruiterTeamPipelineView: View {
    var prospect: WhisperRecruiterService.ProspectRow? = nil
    @State private var model: RecruiterTeamViewModel = RecruiterTeamViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Team pipeline", systemImage: "person.2").font(.headline)
            Text("Only reviewed names, roles, stages and the update you write are published. Contact details, private notes, recordings and Jasper conversations stay private.").font(.caption).foregroundStyle(.secondary)
            if model.isCurrent {
                Picker("Team", selection: $model.business) {
                    Text("Choose a team").tag("")
                    ForEach(model.teams) { team in Text(team.name).tag(team.id) }
                }
                .disabled(model.isBusy)
                .onChange(of: model.business) { _, _ in model.reviewed = false; model.cards = []; model.hasVerified = false }
                if model.teams.isEmpty { Text("An existing Business team is needed for sharing. Your private pipeline works without one.").font(.caption).foregroundStyle(.secondary) }
                if !model.business.isEmpty, model.hasVerified {
                    if let prospect {
                        TextField("Team update", text: $model.update, axis: .vertical).lineLimit(2...6).disabled(model.isBusy)
                            .onChange(of: model.update) { _, _ in model.reviewed = false }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prospect.prospect_display_name ?? prospect.prospect_username ?? "Unnamed").font(.subheadline.bold())
                            Text("\(prospect.suggested_role ?? "unspecified") · \(WhisperRecruiterService.stageLabel(prospect.status))").font(.caption)
                            Text(model.update.isEmpty ? "No team update" : model.update).font(.subheadline)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: .rect(cornerRadius: 14))
                        Toggle("I reviewed this exact card for this team", isOn: $model.reviewed).font(.caption)
                        Button("Publish reviewed card") { Task { await model.publish(prospect, revoke: false) } }.buttonStyle(.borderedProminent).disabled(!model.reviewed || model.isBusy || model.update.count > 1200)
                        if model.cards.contains(where: { $0.id == prospect.id && $0.publisherId == model.owner }) {
                            Button("Revoke my card", role: .destructive) { Task { await model.publish(prospect, revoke: true) } }.disabled(model.isBusy)
                        }
                        Text("Private stage edits never silently change a published card.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(visibleCards, id: \.identity) { card in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(card.name).font(.subheadline.bold())
                            Text("\(card.role) · \(WhisperRecruiterService.stageLabel(card.stage))").font(.caption)
                            Text(card.update).font(.subheadline)
                            Text("Published \(WhisperBackendService.parseISO(card.publishedAt)?.formatted(date: .abbreviated, time: .shortened) ?? card.publishedAt)").font(.caption2).foregroundStyle(.secondary)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: .rect(cornerRadius: 14))
                    }
                    if visibleCards.isEmpty { Text("No reviewed cards published yet.").font(.caption).foregroundStyle(.secondary) }
                }
                if model.isBusy { ProgressView() }
                if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red); Button("Recheck access") { Task { await model.loadTeams(); await model.loadCards() } } }
            } else { Text("Your account changed. Reopen the pipeline.") }
        }
        .task { await model.loadTeams() }
        .task(id: model.business) {
            guard !model.business.isEmpty else { return }
            while !Task.isCancelled {
                await model.loadCards()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .onChange(of: prospect?.status) { _, _ in model.reviewed = false }
    }
    private var visibleCards: [RecruiterTeamCard] {
        guard let prospect else { return model.cards }
        return model.cards.filter { $0.id == prospect.id && $0.publisherId == model.owner }
    }
}
