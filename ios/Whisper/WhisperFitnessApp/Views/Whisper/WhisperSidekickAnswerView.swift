import SwiftUI

struct WhisperSidekickAnswerView: View {
    let turn: WhisperSidekickTurn
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(turn.question).font(.subheadline).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: .rect(cornerRadius: 14))
            Text("Frozen snapshot · \(turn.result.generatedAt) · \(turn.scope)").font(.caption2).foregroundStyle(.secondary)
            if turn.result.insufficient { Text("The chosen sources don’t contain enough evidence yet.").font(.subheadline) }
            ForEach(turn.result.sections, id: \.title) { section in
                Text(section.title).font(.system(.title3, design: .serif))
                ForEach(section.items, id: \.text) { item in
                    Text(item.text).font(.subheadline).textSelection(.enabled)
                    citations(item.sourceIds)
                }
            }
            ForEach(turn.result.actions, id: \.title) { action in
                Text("Suggested follow-up · not sent").font(.caption2).foregroundStyle(.secondary)
                Text(action.title).font(.subheadline.weight(.medium))
                Text("\(action.owner.isEmpty ? "Unassigned" : action.owner) · \(action.when.isEmpty ? "No date stated" : action.when)").font(.caption)
                citations(action.sourceIds)
            }
            if !turn.result.insufficient {
                Button(turn.isKept ? "Kept in Notebook" : "Review & keep privately", action: onReview)
                    .font(.caption).buttonStyle(.bordered).controlSize(.large).disabled(turn.isKept)
            }
        }
    }

    private func citations(_ ids: [String]) -> some View {
        DisclosureGroup("Sources · \(ids.joined(separator: ", "))") {
            ForEach(turn.result.sources.filter { ids.contains($0.id) }) { source in
                VStack(alignment: .leading, spacing: 6) {
                    Text(source.provenance ?? source.id).font(.caption2.weight(.medium))
                    Text(source.text).font(.caption).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
        }.font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
    }
}
