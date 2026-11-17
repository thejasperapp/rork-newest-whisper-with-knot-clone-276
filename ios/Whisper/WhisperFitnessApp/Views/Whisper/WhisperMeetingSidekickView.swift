import SwiftUI

/// The live transcript and account-backed Jasper share one sidekick. Neither owns capture.
struct WhisperMeetingSidekickView: View {
    @Bindable var model: WhisperMeetingSidekickViewModel
    let meetingID: String
    let title: String
    let captureStatus: String
    let interim: String
    let onRetryCapture: () -> Void
    var isArchived: Bool = false
    var isVisible: Bool = true
    var onHide: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var jasper: JasperMeetingsViewModel = JasperMeetingsViewModel()
    @State private var transcriptOpen: Bool = false

    private var highlightedSegments: Set<String> {
        guard let answer = jasper.answers.last else { return [] }
        let ids = Set(answer.result.sections.flatMap { $0.items.flatMap(\.sourceIds) })
        return Set(answer.sources.filter { $0.meetingId == meetingID && ids.contains($0.id) }.map(\.segmentId))
    }
    var body: some View {
        VStack(spacing: 0) {
            if model.isCurrent {
                HStack {
                    JasperSidekickMascot(size: 34, isWorking: jasper.isAsking)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Jasper").font(.headline)
                        Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Label(captureStatus, systemImage: "waveform").font(.caption).foregroundStyle(.secondary)
                        if let failure = WhisperMeetingService.shared.transcriptSaveError { Text(failure).font(.caption).foregroundStyle(.red) }
                    }
                    Spacer()
                    Button { if let onHide { onHide() } else { dismiss() } } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.accessibilityLabel("Minimize Jasper sidekick")
                }.padding(.horizontal, 20).padding(.vertical, 12)
                Divider()
                ScrollView { transcript }.frame(maxHeight: transcriptOpen ? 180 : 70).padding(.horizontal, 16).padding(.top, 8)
                // Inside a live call the call stays primary, so the full-screen Jasper Intelligence handoff is offered only for saved meetings.
                JasperMeetingAssistantView(model: jasper, meetingID: meetingID, embedded: true, allowsJasperIntelligence: isArchived)
            } else { ContentUnavailableView("Sign in to use Jasper", systemImage: "lock") }
        }
        .task(id: "\(scenePhase)-\(isVisible)") {
            guard scenePhase == .active, isVisible else { return }
            while !Task.isCancelled {
                await model.refresh(meetingID: meetingID)
                if isArchived { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .onDisappear { model.notebook.save() }
    }
    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { transcriptOpen.toggle() } } label: {
                HStack { Text("Transcript").font(.subheadline.weight(.semibold)); Text("\(model.rows.count) saved passages").font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: transcriptOpen ? "chevron.up" : "chevron.down").font(.caption) }.frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel(transcriptOpen ? "Hide transcript" : "Show transcript")
            if transcriptOpen {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let error = model.transcriptError { Text(error).font(.caption).foregroundStyle(.red) }
                        else if model.rows.isEmpty { Text(isArchived ? "No saved speech is available. Check the meeting recording for a separately captured transcript." : "No saved speech yet. Check microphone access and capture status above.").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(model.rows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(row.username.isEmpty ? "Speaker" : row.username) · \(String(row.spoken_at.prefix(19)).replacingOccurrences(of: "T", with: " "))").font(.caption2).foregroundStyle(.secondary)
                                Text(row.text).font(.subheadline).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(highlightedSegments.contains(row.id) ? Color.yellow.opacity(0.18) : Color.clear, in: .rect(cornerRadius: 10))
                        }
                        if !interim.isEmpty { Text("Being transcribed · not saved yet\n\(interim)").font(.subheadline).italic().foregroundStyle(.secondary) }
                        if !model.isComplete, !model.rows.isEmpty { Text("Latest 200 passages. Jasper searches saved history separately.").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 4)
                }.frame(maxHeight: 160)
                .overlay(alignment: .top) {
                    if jasper.isScanning {
                        Label("Reading transcript…", systemImage: "sparkles").font(.caption).padding(.horizontal, 14).padding(.vertical, 8).foregroundStyle(.white).background(WhisperBrandGradient.rose, in: Capsule())
                            .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, phase in content.offset(y: phase ? 160 : 0) } animation: { _ in .easeInOut(duration: 2.8) }
                            .allowsHitTesting(false)
                    }
                }
            }
            if !transcriptOpen, let error = model.transcriptError { Text(error).font(.caption).foregroundStyle(.red) }
            if transcriptOpen || model.transcriptError != nil || WhisperMeetingService.shared.transcriptSaveError != nil || captureStatus.localizedCaseInsensitiveContains("paused") || captureStatus.localizedCaseInsensitiveContains("available") {
            HStack {
                Button("Refresh transcript") { Task { await WhisperMeetingService.shared.flushTranscriptQueue(); await model.refresh(meetingID: meetingID) } }.font(.caption).frame(minHeight: 44)
                if !isArchived { Button("Retry capture", action: onRetryCapture).font(.caption).frame(minHeight: 44) }
            }
            }
        }.padding(12).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 18))
    }
}
