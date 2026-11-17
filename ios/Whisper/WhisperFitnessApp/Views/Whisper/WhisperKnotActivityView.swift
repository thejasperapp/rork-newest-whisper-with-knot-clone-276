import SwiftUI

/// Presentation is derived from executor receipts, never model-authored progress.
nonisolated enum WhisperKnotExecutionAppearance {
    static func label(_ result: WhisperKnotShellResult?, state: String, complete: Bool? = nil, truncated: Bool? = nil) -> String {
        guard let result else { return ["running", "dispatching"].contains(state) ? "Waiting for receipt" : state == "review" ? "Preparing" : "Not started" }
        if result.status == "awaiting_approval" { return "Not started" }
        if result.status == "cancelled" { return result.terminationConfirmed ? (result.sessionID == nil ? "Not started" : "Stopped") : "Stop requested" }
        if !result.terminationConfirmed {
            if result.status == "stopping" { return "Stop requested" }
            return result.providerStatus == "live" ? "Working" : "Not confirmed"
        }
        if result.sessionID == nil { return "Not started" }
        if result.exitCode == nil && !(complete ?? result.outputComplete) { return "Not confirmed" }
        if result.status == "failed" || result.exitCode.map({ $0 != 0 }) == true { return "Failed" }
        if !(complete ?? result.outputComplete) || (truncated ?? result.truncated) { return "Output incomplete" }
        return result.status == "completed" && result.exitCode == 0 ? "Step finished" : "Ended"
    }
    static func symbol(_ label: String) -> String {
        switch label {
        case "Step finished": "checkmark.circle.fill"
        case "Working", "Preparing": "circle.dotted"
        case "Failed", "Output incomplete", "Not confirmed": "exclamationmark.circle"
        case "Stopped", "Stop requested": "stop.circle"
        default: "circle"
        }
    }
}

struct WhisperKnotMessageEvent: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let text: String
    let fromUser: Bool
    var pillTimeline: [KnotPillTransition] = []
}

private struct KnotTimelineEntry: Identifiable {
    let id: String
    let date: Date
    let title: String
    let subtitle: String
    let symbol: String
    var task: KnotActivityTask? = nil
}

struct WhisperKnotActivityView: View {
    let bot: WhisperKnotBot
    let conversationID: UUID
    var proposals: [WhisperKnotShellProposal] = []
    var messages: [WhisperKnotMessageEvent] = []
    var working = false
    let activityStore: WhisperKnotActivityStore
    let tasks: [KnotActivityTask]
    var refresh: () -> Void = {}
    var stop: () -> Void = {}
    var resume: (WhisperKnotShellProposal) -> Void = { _ in }
    var continueTask: (WhisperKnotShellProposal) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @State private var invalidated = false
    @State private var selectedTask: KnotActivityTask?
    private var loading: Bool { activityStore.loading }
    private var issue: String? { activityStore.issue }
    private var timeline: [KnotTimelineEntry] {
        guard !invalidated else { return [] }
        return tasks.map { KnotTimelineEntry(id: $0.id, date: $0.date, title: $0.title, subtitle: $0.summary, symbol: $0.symbol, task: $0) }
    }

    var body: some View {
        let grouped = Dictionary(grouping: timeline, by: { Calendar.current.startOfDay(for: $0.date) })
        let days = grouped.keys.sorted(by: >)
        LazyVStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Events").font(.title2.bold())
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button(action: refresh) { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .accessibilityLabel("Refresh events")
            }
            if let issue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
            if timeline.isEmpty && !loading {
                ContentUnavailableView("A quieter conversation", systemImage: "list.bullet.rectangle", description: Text("One entry per task. Open it to see the conversation, recorded steps and receipts."))
            }
            ForEach(days, id: \.self) { day in
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text(dayTitle(day)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
                    ForEach(grouped[day] ?? []) { entry in
                        Button { selectedTask = entry.task } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: entry.symbol).font(.system(size: 18)).frame(width: 42, height: 42)
                                    .background(.primary.opacity(0.06), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                                    if entry.date.timeIntervalSince1970 > 0 { Text(entry.date, style: .time).font(.caption2).foregroundStyle(.tertiary) }
                                }
                                Spacer(minLength: 4)
                                if entry.task != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 12) }
                            }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                                .padding(.vertical, 8).contentShape(.rect)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if working { Button("Stop current work", role: .destructive, action: stop).buttonStyle(.bordered).frame(minHeight: 44) }
        }
        .sheet(item: $selectedTask) { task in
            taskSheet(timeline.first(where: { $0.id == task.id })?.task ?? task)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in clear() }
    }

    private func taskSheet(_ task: KnotActivityTask) -> some View {
        let steps = task.commandSteps
        return NavigationStack {
            VStack(spacing: 0) {
                // Both controls belong to this fixed row, not the navigation bar
                // or the scrolling title. Long Events keep dismissal in reach.
                WhisperKnotTaskSheetHeader(summary: task.summary, active: task.active) { selectedTask = nil }
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 6)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.displayTitle).font(.headline).fixedSize(horizontal: false, vertical: true)
                        if let request = task.messages.first(where: \.fromUser) {
                            Text(request.text).font(.body).textSelection(.enabled)
                        }
                        if task.date != .distantPast {
                            Text(task.date, style: .time).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 16)
                    Divider()
                    Text(task.overview).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                    Divider()
                    VStack(alignment: .leading, spacing: 22) {
                    if !steps.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("MAIN").font(.system(.caption, design: .monospaced, weight: .medium)).foregroundStyle(.primary)
                            VStack(spacing: 0) {
                                ForEach(steps) { step in
                                    NavigationLink { stepEvidence(step, task: task) } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            WhisperKnotStepIndicator(state: step.state).frame(width: 24, height: 24)
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(step.stageWord).font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
                                                if step.state != "Done" { Text(step.state).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                                            }.padding(.top, 2)
                                            Spacer(minLength: 4)
                                            Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(.tertiary).padding(.top, 6)
                                        }.frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                                            .padding(.bottom, 22).contentShape(.rect)
                                            .background(alignment: .topLeading) {
                                                if step.id != steps.last?.id {
                                                    GeometryReader { geometry in
                                                        Path { path in
                                                            path.move(to: CGPoint(x: 12, y: 27))
                                                            path.addLine(to: CGPoint(x: 12, y: geometry.size.height - 3))
                                                        }
                                                        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                                    }.allowsHitTesting(false)
                                                }
                                            }
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if !task.documents.isEmpty {
                        WhisperKnotDocumentRows(documents: task.documents, bot: bot, conversationID: conversationID, enabled: !invalidated)
                    }
                    if working { Button("Stop current work", role: .destructive, action: stop).frame(minHeight: 44) }
                    }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 24)
                }.frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
            }
            .background(Color.black)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }.environment(\.colorScheme, .dark).tint(.white).presentationDetents([.large]).presentationDragIndicator(.hidden)
            .presentationBackground(Color.black)
    }
    private func stepEvidence(_ step: KnotActivityStep, task: KnotActivityTask) -> some View {
        WhisperKnotStageDetail(step: step, events: task.executorEvents.filter { event in step.records.contains { $0.id.lowercased() == event.proposalID.lowercased() } }, bot: bot, conversationID: conversationID, enabled: !invalidated)
    }
    @ViewBuilder private func executionEvidence(_ records: [WhisperKnotShellReplay.Record], events: [WhisperKnotExecutorEvent]) -> some View {
        Section("Execution receipts") {
            ForEach(records) { record in
                NavigationLink(record.spec.title) {
                    WhisperKnotReadableExecutionView(record: record, proposal: proposals.first(where: { $0.id == record.id }) ?? record.proposal)
                }
                if let proposal = proposals.first(where: { $0.id == record.id }), !working {
                    if proposal.reviewable {
                        Button("Resume unstarted task") { selectedTask = nil; resume(proposal) }
                    }
                    if !proposal.continued, proposal.result?.terminationConfirmed == true,
                       proposal.result?.sessionID != nil, proposal.result?.status != "cancelled" {
                        Button("Continue from saved result") { selectedTask = nil; continueTask(proposal) }
                    }
                }
            }
        }
        Section("Executor events") {
            ForEach(events) { event in
                NavigationLink(event.title) {
                    WhisperKnotExecutorEventDetail(event: event)
                }
            }
        }
    }
    private func dayTitle(_ date: Date) -> String {
        if date.timeIntervalSince1970 <= 0 { return "Earlier · date unavailable" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
    private func clear() { invalidated = true; selectedTask = nil }
}

/// One layout row owns both controls, so status and dismissal can never drift
/// into separate navigation/scroll coordinate systems.
struct WhisperKnotTaskSheetHeader: View {
    let summary: String
    let active: Bool
    let close: () -> Void
    private var tint: Color { summary == "Done" ? .green : active || ["Failed", "Needs attention", "Not confirmed"].contains(summary) ? .orange : .secondary }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(summary == "Done" ? "Complete" : active ? "In progress" : summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 5))
                .accessibilityIdentifier("knot-event-status")
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.1), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }.buttonStyle(.plain).accessibilityLabel("Close task details")
                .accessibilityIdentifier("knot-event-close")
        }
    }
}

/// A truthful shell preview, not a simulated browser or a promise of an always-on desktop.
struct WhisperKnotComputerPreview: View {
    let proposal: WhisperKnotShellProposal
    var open: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer").font(.title3).frame(width: 42, height: 42).background(.blue.opacity(0.1), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Linux workspace").font(.subheadline.weight(.semibold))
                    Text(proposal.label + " · recorded shell output").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(proposal.spec.title).font(.system(.caption, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                Text(preview).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white).lineLimit(7).frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            }.padding(16).background(Color(white: 0.075), in: .rect(cornerRadius: 14))
            if let open {
                Button(action: open) { Text("Open workspace").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }
    private var preview: String {
        guard let result = proposal.result else { return "Waiting for workspace output…" }
        let text = (result.stdout + "\n" + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No output received." : String(text.suffix(1000))
    }
}

struct WhisperKnotComputerView: View {
    let bot: WhisperKnotBot
    let conversationID: UUID
    var proposal: WhisperKnotShellProposal?
    var stop: () -> Void = {}
    @State private var connection: String = "Checking shell connection…"
    @State private var refreshID = UUID()
    @State private var invalidated = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WhisperKnotBrowserView(bot: bot, conversationID: conversationID, onStopTask: stop)
                .id("browser-\(bot.rawValue)-\(conversationID.uuidString)")
            if let proposal, !invalidated {
                WhisperKnotComputerPreview(proposal: proposal)
                if ["dispatching", "running"].contains(proposal.state) { Button("Stop task", role: .destructive, action: stop).buttonStyle(.bordered).frame(minHeight: 44) }
            }
            DisclosureGroup("Workspace connection") {
                Label(connection, systemImage: "terminal").font(.subheadline).foregroundStyle(.secondary)
                Button("Refresh connection") { refreshID = UUID() }.frame(minHeight: 44)
                NavigationLink { WhisperKnotShellInfoView(bot: bot) } label: { Label("Workspace privacy & limits", systemImage: "info.circle").frame(minHeight: 44) }
            }.font(.subheadline)
        }
        .task(id: refreshID) {
            do {
                let data = try await WhisperKnotShellEvidenceService.fetch("capabilities")
                let value = try JSONDecoder().decode(WhisperKnotLiveCapabilities.self, from: data)
                guard !invalidated, !Task.isCancelled else { return }
                connection = value.ok && value.service == "knot-sidecar" ? "Shell connected" : "Shell connection unavailable"
            } catch { if !invalidated { connection = "Shell connection unavailable" } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in invalidated = true; connection = "Connection cleared" }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in invalidated = true; connection = "Connection cleared" }
    }
}
