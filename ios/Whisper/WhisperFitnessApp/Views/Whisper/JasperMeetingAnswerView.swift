import SwiftUI

/// A cited answer keeps its dated evidence; Jasper's general knowledge is labeled and never dressed up as meeting speech.
struct JasperMeetingAnswerView: View {
    let answer: JasperMeetingAnswer
    var onSeekRecording: ((String, Double) -> Void)? = nil
    /// Tapping a suggested next question asks it through the same consented scope.
    var onFollowup: ((String) -> Void)? = nil
    /// Hands the question to full-screen Jasper Intelligence for deeper general exploration.
    var onContinueInJasper: ((String) -> Void)? = nil
    @State private var selected: JasperMeetingAnswer.Evidence?

    private var grounding: String { answer.groundingLabel }
    private var isKnowledgeGrounded: Bool { grounding != "evidence" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(answer.question).font(.subheadline).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: .rect(cornerRadius: 16))
            header
            readingLine
            notices
            ForEach(answer.result.sections, id: \.title) { section in sectionView(section) }
            actionsView
            followupsView
            continueButton
            coverageDisclosure
        }
        .sheet(item: $selected) { evidence in JasperMeetingSourceView(evidence: evidence) }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Jasper · \(answer.scope)", systemImage: "sparkles").font(.caption.weight(.medium))
            groundingBadge
        }
    }

    private var groundingBadge: some View {
        let title = grounding == "knowledge" ? "Jasper’s knowledge · not from your meetings" : grounding == "mixed" ? "Meeting evidence + Jasper’s knowledge" : "Cited from your meetings"
        return Label(title, systemImage: isKnowledgeGrounded ? "brain" : "text.book.closed")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(isKnowledgeGrounded ? Color.green : Color.primary)
            .background(isKnowledgeGrounded ? Color.green.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
            .accessibilityLabel(title)
    }

    @ViewBuilder private var readingLine: some View {
        let reading = answer.reading
        if reading.passages > 0 {
            Text(readingDescription(reading)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readingDescription(_ reading: JasperMeetingAnswer.Reading) -> String {
        var text = "Read \(reading.passages) passage\(reading.passages == 1 ? "" : "s")"
        if reading.notes > 0 { text += " (\(reading.notes) from saved notes)" }
        if reading.hasRecording { text += " from your selected recording" }
        text += " across \(reading.meetings.count) meeting\(reading.meetings.count == 1 ? "" : "s"): "
        text += reading.meetings.map { meeting in
            let date = Self.shortDate(meeting.date)
            return date.isEmpty ? meeting.title : "\(meeting.title) (\(date))"
        }.joined(separator: ", ")
        return text + "."
    }

    @ViewBuilder private var notices: some View {
        if answer.partialEvidence == true {
            Text("Partial evidence · I checked selected excerpts, not every word. Other context or later corrections may be missing.")
                .font(.caption).foregroundStyle(.secondary).padding(12).background(.quaternary, in: .rect(cornerRadius: 12))
        }
        if answer.result.insufficient {
            Text("I didn’t find a useful match in what I checked yet. Try a person, topic or date, or choose a different meeting scope. That doesn’t mean it was never discussed.").font(.subheadline).lineSpacing(5)
            if let onContinueInJasper {
                Button { onContinueInJasper(answer.question) } label: { Label("Need general help instead? Continue with Knot", systemImage: "arrow.up.forward.app").font(.caption.weight(.medium)).frame(minHeight: 44) }.tint(.primary)
            }
        }
        if answer.result.related == true {
            Text("I didn’t find an exact answer in what I checked, but I found this related context.").font(.subheadline.weight(.medium)).lineSpacing(5)
        }
        if let note = answer.noteContext {
            Text("Suggested connections · highlighted quotes from “\(note.title)”. Review the meeting evidence before keeping them; your original note is unchanged.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sectionView(_ section: JasperMeetingAnswer.Section) -> some View {
        let knowledge = !section.items.isEmpty && section.items.allSatisfy(\.isKnowledge)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if knowledge { Image(systemName: "brain") }
                Text(section.title)
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(section.items, id: \.text) { item in itemView(item) }
        }
        .padding(knowledge ? 12 : 0)
        .background(knowledge ? Color.green.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(section.title)
    }

    private func itemView(_ item: JasperMeetingAnswer.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quote = item.noteQuote {
                Text(quote).font(.subheadline).textSelection(.enabled).padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.18), in: .rect(cornerRadius: 10))
            }
            Text(item.text).font(.subheadline).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if item.isKnowledge {
                Text("Jasper’s knowledge · not said in your meetings · verify important facts").font(.caption2.weight(.medium)).foregroundStyle(Color.green)
            } else {
                references(item.sourceIds)
            }
        }
    }

    @ViewBuilder private var actionsView: some View {
        if !answer.result.actions.isEmpty { Text("Suggested next steps · drafts").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
        ForEach(answer.result.actions, id: \.title) { action in
            VStack(alignment: .leading, spacing: 8) {
                Text(action.title).font(.subheadline.weight(.medium))
                Text("\(action.owner.isEmpty ? "Owner not stated" : action.owner) · \(action.when.isEmpty ? "Date not stated" : action.when)").font(.caption).foregroundStyle(.secondary)
                references(action.sourceIds)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: .rect(cornerRadius: 14))
        }
    }

    @ViewBuilder private var followupsView: some View {
        if let onFollowup, !answer.followups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(answer.followups, id: \.self) { prompt in
                    Button { onFollowup(prompt) } label: {
                        Label(prompt, systemImage: "arrow.turn.down.right").font(.caption.weight(.medium)).multilineTextAlignment(.leading)
                            .padding(.horizontal, 12).frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }.accessibilityLabel("Suggested follow-up questions")
        }
    }

    @ViewBuilder private var continueButton: some View {
        if let onContinueInJasper, isKnowledgeGrounded, !answer.result.insufficient {
            Button { onContinueInJasper(answer.question) } label: { Label("Continue with Knot", systemImage: "arrow.up.forward.app").font(.caption.weight(.medium)).frame(minHeight: 44) }.tint(.primary)
        }
    }

    private var coverageDisclosure: some View {
        DisclosureGroup("What Jasper searched") {
            Text(answer.coverage).font(.caption).foregroundStyle(.secondary)
            if let note = answer.noteContext { Text(note.text).font(.caption).textSelection(.enabled).padding(.top, 8) }
        }.font(.caption).frame(minHeight: 44)
    }

    private func references(_ ids: [String]) -> some View {
        DisclosureGroup("\(ids.count) source\(ids.count == 1 ? "" : "s") · inspect quotes") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(answer.sources.filter { ids.contains($0.id) }) { source in
                    Button { selected = source } label: {
                        Label("\(source.meetingTitle) · \(String(source.spokenAt.prefix(10)))", systemImage: "quote.opening")
                            .font(.caption).multilineTextAlignment(.leading).frame(minHeight: 44)
                    }.tint(.primary)
                    if source.kind == "summary" { Text("Saved notes · not verbatim speech").font(.caption2).foregroundStyle(.secondary) }
                    if let recordingID = source.recordingId, let position = source.position {
                        Button("Recording \(WhisperRecordingArchive.time(position))\(source.timing == "chunk" ? " · Approx." : "")") { onSeekRecording?(recordingID, position) }.font(.caption).frame(minHeight: 44).disabled(onSeekRecording == nil)
                    }
                }
            }
        }.font(.caption).tint(.secondary).frame(minHeight: 44)
    }

    private static func shortDate(_ iso: String) -> String {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return String(iso.prefix(10)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
