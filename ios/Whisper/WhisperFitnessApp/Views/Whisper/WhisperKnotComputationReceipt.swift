import SwiftUI

/// An actual arithmetic-tool result, never a fabricated shell session or exit code.
nonisolated struct WhisperKnotCalculationReceipt: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let conversationID: UUID
    let sourceMessageID: UUID
    let expression: String
    let value: Double
    let completedAt: Double
    var valid: Bool { !expression.isEmpty && expression.utf8.count <= 2000 && value.isFinite && completedAt.isFinite && completedAt > 0 }
}

struct WhisperKnotCalculationCard: View {
    let receipt: WhisperKnotCalculationReceipt
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calculation completed", systemImage: "function").font(.subheadline.weight(.semibold))
            Text(receipt.expression).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            Text(receipt.value.formatted(.number.precision(.significantDigits(1...15))))
                .font(.title3.weight(.semibold)).textSelection(.enabled)
            Text("Arithmetic tool · finite-precision result").font(.caption).foregroundStyle(.secondary)
        }.modifier(WhisperKnotPanel())
            .accessibilityIdentifier("knot.calculation.\(receipt.id)")
    }
}

/// Display-only receipt. Opening this card can never dispatch, resume or replay.
struct WhisperKnotExecutionReceiptCard: View {
    let proposal: WhisperKnotShellProposal
    let stop: (() -> Void)?
    @State private var showEvents = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Code execution", systemImage: "function").font(.subheadline.weight(.semibold))
            Text(proposal.executionStatus).font(.caption).foregroundStyle(.secondary)
            if let result = proposal.result, !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(String(result.stdout.prefix(600))).font(.system(.caption, design: .monospaced))
                    .lineLimit(7).textSelection(.enabled)
                if result.stdout.count > 600 || result.truncated { Text("Output preview · full details available").font(.caption2).foregroundStyle(.secondary) }
            }
            HStack {
                Button("Details") { showEvents = true }.font(.subheadline)
                Spacer()
                if let stop { Button("Stop", role: .destructive, action: stop).font(.subheadline) }
            }
        }.modifier(WhisperKnotPanel())
            .accessibilityIdentifier("knot.execution.\(proposal.id)")
            .sheet(isPresented: $showEvents) { WhisperKnotShellEventsView(proposal: proposal, continueTask: nil) }
    }
}
