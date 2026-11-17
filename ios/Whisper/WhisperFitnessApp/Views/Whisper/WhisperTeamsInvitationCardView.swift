import SwiftUI
import UIKit

/// Message-bound projection. Review opens Teams; no acceptance controls live in Social.
struct WhisperTeamsInvitationCardView: View {
    let message: WhisperMessageRow
    @Environment(\.scenePhase) private var phase
    @State private var card: WhisperTeamsInvitationCard?
    @State private var error: String?
    @State private var attempt: Int = 0
    @State private var opening: Bool = false
    @State private var openTask: Task<Void, Never>?
    @State private var operation: UUID = UUID()
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    @State private var invalidated: Bool = false
    private var isCurrent: Bool { !closed && !invalidated && generation == AccountStorage.generation && phase == .active }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Whisper Teams", systemImage: "person.2.crop.square.stack")
                .font(.subheadline.weight(.semibold))
            if let card, isCurrent {
                Text(card.teamName).font(.headline).lineLimit(3)
                Text(card.status == "pending" && card.isExpired ? "Invitation expired" : card.statusLabel)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Reported by Teams · \(Date(timeIntervalSince1970: Double(card.occurredAt) / 1000).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                if card.canOpen && !card.isExpired {
                    Button(opening ? "Checking invitation…" : "Review in Teams") { open() }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.bordered).disabled(opening)
                    Text("You'll review the invitation in Teams. Opening it does not join the team.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if error == nil { ProgressView("Checking invitation…").font(.caption) }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if let syncError = WhisperPushPreferenceSync.shared.teamsPrivacyError,
               message.to_user_id.lowercased() == AccountStorage.currentUserID.lowercased() {
                Text(syncError).font(.caption).foregroundStyle(.secondary)
                Button("Retry privacy sync") { WhisperPushPreferenceSync.shared.refresh() }.frame(minHeight: 44)
            }
            Button("Refresh status") { attempt += 1 }.font(.caption.weight(.semibold))
                .frame(minHeight: 44).disabled(opening || !isCurrent)
        }
        .padding(16).frame(maxWidth: 280, alignment: .leading)
        .foregroundStyle(.primary).background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.10), lineWidth: 1) }
        .accessibilityElement(children: .contain).accessibilityLabel("Team invitation")
        .onAppear { closed = false }
        .task(id: "\(message.id)-\(attempt)-\(phase == .active)") {
            guard isCurrent else { return }
            await reload()
            while !Task.isCancelled && isCurrent {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if !opening { await reload() }
            }
        }
        .onChange(of: phase) { _, value in if value != .active { clear() } }
        .onDisappear { closed = true; clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in invalidated = true; clear() }
    }
    private func clear() { operation = UUID(); openTask?.cancel(); openTask = nil; opening = false; card = nil; error = nil }
    private func reload() async {
        guard isCurrent, !opening else { return }
        let id = UUID(); operation = id
        do {
            let value = try await WhisperTeamsInvitationService.load(message: message)
            guard !Task.isCancelled, isCurrent, id == operation else { return }
            card = value; error = nil
        } catch {
            guard !Task.isCancelled, isCurrent, id == operation else { return }
            card = nil; self.error = WhisperTeamsInvitationService.Failure.unavailable.localizedDescription
        }
    }
    private func open() {
        guard isCurrent, !opening, let previous = card, previous.canOpen, !previous.isExpired else { return }
        let id = UUID(); operation = id; opening = true
        openTask = Task {
            defer { if operation == id { opening = false; openTask = nil } }
            do {
                let value = try await WhisperTeamsInvitationService.load(message: message)
                guard !Task.isCancelled, isCurrent, id == operation else { return }
                card = value
                guard value.invitationId == previous.invitationId, value.canOpen, !value.isExpired, let url = value.nativeURL else { return }
                let opened = await UIApplication.shared.open(url)
                guard !Task.isCancelled, generation == AccountStorage.generation, id == operation else { return }
                if !opened { error = "Couldn't open Whisper Teams. An approved browser return link isn't available yet." }
            } catch {
                guard !Task.isCancelled, isCurrent, id == operation else { return }
                card = nil; self.error = WhisperTeamsInvitationService.Failure.unavailable.localizedDescription
            }
        }
    }
}
