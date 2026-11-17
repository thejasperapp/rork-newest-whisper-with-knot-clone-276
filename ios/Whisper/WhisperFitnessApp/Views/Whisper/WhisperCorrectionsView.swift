import SwiftUI
import Supabase

nonisolated struct WhisperReviewedSnapshot: Codable, Sendable {
    let caption: String?
    let media_urls: [String]?
}
nonisolated struct WhisperCorrectionRow: Codable, Identifiable, Sendable {
    let id: String
    let report_id: String
    let post_id: String
    let author_id: String
    let reviewed_snapshot: WhisperReviewedSnapshot
    let explanation: String
    let sources: [String]
    let state: String
    let updated_at: String
}
nonisolated struct WhisperCorrectionAppeal: Codable, Identifiable, Sendable {
    let id: String
    let correction_id: String
    let body: String
    let status: String
    let outcome: String?
}
nonisolated struct WhisperContactRestriction: Codable, Identifiable, Sendable {
    let id: String
    let reason: String
    let review_at: String
    let expires_at: String
    let revoked_at: String?
}
nonisolated struct WhisperReviewReport: Codable, Identifiable, Sendable {
    let id: String
    let reason: String
    let details: String?
    let status: String
    let post_snapshot: WhisperReviewedSnapshot?
}
nonisolated struct WhisperLegacyAppeal: Codable, Identifiable, Sendable {
    let id: String
    let body: String
    let status: String
}
nonisolated struct WhisperCorrectionEvent: Codable, Identifiable, Sendable {
    let id: String
    let action: String
    let explanation: String
    let created_at: String
}

@MainActor
struct WhisperReviewSession {
    let owner: String = AccountStorage.currentUserID
    let generation: UUID = AccountStorage.generation
    func check() throws {
        guard !Task.isCancelled, generation == AccountStorage.generation,
              SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == owner.lowercased() else { throw CancellationError() }
    }
}

struct WhisperCorrectionContent: View {
    let row: WhisperCorrectionRow
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.state == "withdrawn" ? "Correction withdrawn" : "Correction").font(.headline)
            Text(row.explanation).font(.subheadline)
            DisclosureGroup("Reviewed version & sources") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.reviewed_snapshot.caption ?? "Media post — no caption").font(.subheadline).textSelection(.enabled)
                    Text("This notice refers to the version reviewed and stays with the post after edits.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array((row.reviewed_snapshot.media_urls ?? []).enumerated()), id: \.offset) { index, raw in
                        if let url = URL(string: raw), url.scheme == "https" { Link("Reviewed media \(index + 1)", destination: url) }
                    }
                    ForEach(Array(row.sources.enumerated()), id: \.offset) { index, raw in
                        if let url = URL(string: raw), url.scheme == "https" { Link("Source \(index + 1): \(url.host() ?? "source")", destination: url) }
                    }
                }.padding(.top, 8)
            }.font(.subheadline)
        }
    }
}

struct WhisperPostCorrectionNotice: View {
    let postID: String
    var compact = false
    @State private var showDetails = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var rows: [WhisperCorrectionRow] = []
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                if !rows.isEmpty {
                    Button { showDetails = true } label: { Label("Reviewed correction · View details", systemImage: "info.circle").font(.subheadline).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                        .buttonStyle(.plain)
                }
            } else {
                ForEach(rows) { row in
                    WhisperCorrectionContent(row: row)
                        .padding(12).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if failed { Button("Correction status unavailable · Retry") { Task { await load() } }.font(.caption) }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                List { ForEach(rows) { row in WhisperCorrectionContent(row: row) } }
                    .navigationTitle("Reviewed correction")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDetails = false } } }
            }
        }
        .task(id: "\(postID)-\(AccountStorage.generation)-\(scenePhase == .active)") { guard scenePhase == .active else { return }; await load() }
    }
    @MainActor private func load() async {
        let session = WhisperReviewSession()
        do {
            try session.check()
            let result: [WhisperCorrectionRow] = try await SupabaseService.shared.client.from("whisper_corrections").select().eq("post_id", value: postID).order("updated_at", ascending: false).execute().value
            try session.check(); rows = result; failed = false
        } catch is CancellationError { } catch { guard session.generation == AccountStorage.generation else { return }; failed = true }
    }
}

struct WhisperDecisionInboxNotice: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var version: String?
    @State private var seen: String?
    @State private var presented = false
    private var storageKey: String { "whisper:decision-notice:\(AccountStorage.currentUserID)" }
    var body: some View {
        Group {
            if let version, version != seen {
                HStack(alignment: .top, spacing: 12) {
                    Button { acknowledge(version); presented = true } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("A decision on your post has been updated").font(.subheadline.weight(.semibold))
                            Text("View private decisions & appeals").font(.caption).underline()
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).frame(minHeight: 44)
                    Button("Dismiss") { acknowledge(version) }.font(.caption).frame(minHeight: 44)
                }.padding(12).background(.regularMaterial)
            }
        }
        .sheet(isPresented: $presented) { WhisperDecisionsView().id(AccountStorage.generation) }
        .task(id: "\(AccountStorage.generation)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            let session = WhisperReviewSession()
            seen = UserDefaults.standard.string(forKey: storageKey)
            do {
                while !Task.isCancelled {
                    try session.check()
                    let result: [WhisperCorrectionRow] = try await SupabaseService.shared.client.from("whisper_corrections").select().eq("author_id", value: session.owner).order("updated_at", ascending: false).limit(1).execute().value
                    try session.check()
                    version = result.first.map { "\($0.id):\($0.updated_at)" }
                    try await Task.sleep(for: .seconds(60))
                }
            } catch { /* Decisions remain available in Settings if this optional alert cannot refresh. */ }
        }
    }
    private func acknowledge(_ value: String) { seen = value; UserDefaults.standard.set(value, forKey: storageKey) }
}

struct WhisperDecisionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var corrections: [WhisperCorrectionRow] = []
    @State private var appeals: [WhisperCorrectionAppeal] = []
    @State private var restrictions: [WhisperContactRestriction] = []
    @State private var legacy: [WhisperLegacyAppeal] = []
    @State private var reviewer = false
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Private decisions for this account. A correction concerns a reviewed post, not your identity. AI analysis and report volume do not issue penalties.").font(.subheadline)
                    Text("Historical username-only appeals are preserved for staff review. If yours is not listed, contact Support to confirm ownership; a reused username does not grant access.").font(.caption).foregroundStyle(.secondary)
                    if loading { ProgressView("Loading decisions…") }
                    if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await load() } } }
                    if !loading && error == nil && corrections.isEmpty { Text("No reviewed corrections for your posts.").foregroundStyle(.secondary) }
                }
                ForEach(corrections) { row in
                    Section {
                        WhisperCorrectionContent(row: row)
                        if let appeal = appeals.first(where: { $0.correction_id == row.id }) {
                            Text("Appeal: \(appeal.status)").font(.headline)
                            Text(appeal.body)
                            if let outcome = appeal.outcome { Text("Review outcome: \(outcome)") }
                        } else {
                            NavigationLink("Respond or appeal") { WhisperCorrectionAppealForm(correctionID: row.id) }
                        }
                    }
                }
                ForEach(restrictions) { row in
                    Section("Separate messaging restriction") {
                        Text(row.reason)
                        Text("Review: \(row.review_at)").font(.caption)
                        Text("Expiry: \(row.expires_at)").font(.caption)
                        if row.revoked_at != nil { Text("Revoked").foregroundStyle(.secondary) }
                    }
                }
                ForEach(legacy) { row in
                    Section("Historical appeal · \(row.status)") {
                        Text(row.body)
                        Text("Preserved from the retired system. Not a new finding or a public label.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Contact permissions") { NavigationLink("Explicitly permitted contacts") { WhisperContactPermissionsView() } }
                if reviewer { Section("Authorized review") { NavigationLink("Correction review queue") { WhisperCorrectionReviewQueue() } } }
            }
            .navigationTitle("Decisions & appeals").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task(id: AccountStorage.generation) { await load() }
        }
    }
    @MainActor private func load() async {
        let session = WhisperReviewSession(); let client = SupabaseService.shared.client
        loading = true; error = nil; corrections = []; appeals = []; restrictions = []; legacy = []; reviewer = false
        do {
            try session.check()
            let c: [WhisperCorrectionRow] = try await client.from("whisper_corrections").select().eq("author_id", value: session.owner).order("updated_at", ascending: false).execute().value
            try session.check()
            let a: [WhisperCorrectionAppeal] = try await client.from("whisper_correction_appeals").select().eq("author_id", value: session.owner).execute().value
            try session.check()
            let r: [WhisperContactRestriction] = try await client.from("whisper_contact_restrictions").select().eq("user_id", value: session.owner).execute().value
            try session.check()
            let l: [WhisperLegacyAppeal] = try await client.from("whisper_liar_appeals").select("id,body,status").order("created_at", ascending: false).limit(50).execute().value
            try session.check()
            let authorized: Bool = try await client.rpc("whisper_is_reviewer").execute().value
            try session.check(); corrections = c; appeals = a; restrictions = r; legacy = l; reviewer = authorized; loading = false
        } catch is CancellationError { } catch { guard session.generation == AccountStorage.generation else { return }; loading = false; self.error = "Decisions could not be loaded. Please retry." }
    }
}

struct WhisperCorrectionAppealForm: View {
    let correctionID: String
    @State private var bodyText = ""
    @State private var sending = false
    @State private var received = false
    @State private var failed = false
    var body: some View {
        Form {
            Section("Your response or appeal") { TextEditor(text: $bodyText).frame(minHeight: 140).disabled(sending || received) }
            Section {
                Button(received ? "Appeal received" : sending ? "Submitting…" : "Submit appeal") { Task { await submit() } }
                    .disabled(sending || received || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || bodyText.count > 4000)
                if failed { Text("Appeal not confirmed. Your text is still here. Reopen decisions to check before retrying.").foregroundStyle(.red) }
                Text("Your appeal stays available in Decisions & appeals, including its reviewed outcome.").font(.caption)
            }
        }.navigationTitle("Appeal correction")
    }
    @MainActor private func submit() async {
        let session = WhisperReviewSession(); sending = true; failed = false
        nonisolated struct Params: Encodable, Sendable { let p_correction_id: String; let p_body: String }
        do {
            try session.check()
            let receipt: UUID = try await SupabaseService.shared.client.rpc("whisper_appeal_correction", params: Params(p_correction_id: correctionID, p_body: bodyText)).execute().value
            try session.check(); _ = receipt; received = true; sending = false
        } catch is CancellationError { } catch { guard session.generation == AccountStorage.generation else { return }; sending = false; failed = true }
    }
}

struct WhisperCorrectionReviewQueue: View {
    @State private var reports: [WhisperReviewReport] = []
    @State private var corrections: [WhisperCorrectionRow] = []
    @State private var appeals: [WhisperCorrectionAppeal] = []
    @State private var history: [WhisperCorrectionEvent] = []
    @State private var failed = false
    var body: some View {
        List {
            Section { Text("Review the saved version and independent sources. Opinions, satire, uncertainty, AI verdicts, and report counts are not proof. Decisions and appeals require independent reviewers.").font(.subheadline) }
            if failed { Section { Button("Queue unavailable · Retry") { Task { await load() } } } }
            Section("Post reports") {
                ForEach(reports) { row in
                    NavigationLink { WhisperCorrectionDecisionForm(report: row, appeal: nil, correction: corrections.first { $0.report_id == row.id }) } label: {
                        VStack(alignment: .leading) { Text("\(row.reason) · \(row.status)"); Text(row.post_snapshot?.caption ?? "Historical report — no saved version").font(.caption).lineLimit(3) }
                    }.disabled(row.post_snapshot == nil)
                }
            }
            Section("Pending appeals") {
                ForEach(appeals) { appeal in
                    if let correction = corrections.first(where: { $0.id == appeal.correction_id }), let report = reports.first(where: { $0.id == correction.report_id }) {
                        NavigationLink { WhisperCorrectionDecisionForm(report: report, appeal: appeal, correction: correction) } label: { Text(appeal.body).lineLimit(4) }
                    }
                }
            }
            Section("Action history") { ForEach(history) { event in VStack(alignment: .leading) { Text(event.action).font(.headline); Text(event.explanation); Text(event.created_at).font(.caption) } } }
        }.navigationTitle("Correction review").task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async {
        let session = WhisperReviewSession(); let client = SupabaseService.shared.client
        do {
            try session.check()
            var r: [WhisperReviewReport] = try await client.from("whisper_reports").select("id,reason,details,status,post_snapshot").in("target_kind", values: ["post", "reel"]).order("created_at", ascending: false).limit(100).execute().value
            try session.check()
            var c: [WhisperCorrectionRow] = try await client.from("whisper_corrections").select().order("updated_at", ascending: false).limit(100).execute().value
            try session.check()
            let a: [WhisperCorrectionAppeal] = try await client.from("whisper_correction_appeals").select().eq("status", value: "pending").execute().value
            try session.check()
            let h: [WhisperCorrectionEvent] = try await client.from("whisper_correction_history").select().order("created_at", ascending: false).limit(100).execute().value
            try session.check()
            let missingCorrections = Array(Set(a.map(\.correction_id).filter { id in !c.contains { $0.id == id } }))
            for start in stride(from: 0, to: missingCorrections.count, by: 100) {
                let ids = Array(missingCorrections[start..<min(start + 100, missingCorrections.count)])
                let extra: [WhisperCorrectionRow] = try await client.from("whisper_corrections").select().in("id", values: ids).execute().value
                try session.check(); c.append(contentsOf: extra)
            }
            let appealed = Set(a.map(\.correction_id))
            let missingReports = Array(Set(c.filter { appealed.contains($0.id) }.map(\.report_id).filter { id in !r.contains { $0.id == id } }))
            for start in stride(from: 0, to: missingReports.count, by: 100) {
                let ids = Array(missingReports[start..<min(start + 100, missingReports.count)])
                let extra: [WhisperReviewReport] = try await client.from("whisper_reports").select("id,reason,details,status,post_snapshot").in("id", values: ids).execute().value
                try session.check(); r.append(contentsOf: extra)
            }
            try session.check(); reports = r; corrections = c; appeals = a; history = h; failed = false
        } catch is CancellationError { } catch { guard session.generation == AccountStorage.generation else { return }; failed = true }
    }
}

struct WhisperCorrectionDecisionForm: View {
    let report: WhisperReviewReport
    let appeal: WhisperCorrectionAppeal?
    let correction: WhisperCorrectionRow?
    @State private var explanation = ""
    @State private var sources = ""
    @State private var outcome = "active"
    @State private var sending = false
    @State private var received = false
    @State private var failed = false
    var body: some View {
        Form {
            Section("Original reported version") {
                Text(report.post_snapshot?.caption ?? "No saved version")
                if let details = report.details { Text(details) }
                ForEach(Array((report.post_snapshot?.media_urls ?? []).enumerated()), id: \.offset) { index, raw in
                    if let url = URL(string: raw), url.scheme == "https" { Link("Reviewed media \(index + 1)", destination: url) }
                }
            }
            if let appeal { Section("Author’s appeal") { Text(appeal.body) } }
            if let correction { Section("Existing decision") { WhisperCorrectionContent(row: correction) } }
            Section("Human review reason") { TextEditor(text: $explanation).frame(minHeight: 120) }
            Section("HTTPS sources — one per line") { TextEditor(text: $sources).frame(minHeight: 90).textInputAutocapitalization(.never).autocorrectionDisabled() }
            Section {
                Picker("Decision", selection: $outcome) {
                    Text(appeal == nil ? "Publish / update" : "Uphold").tag("active")
                    if appeal != nil { Text("Update").tag("updated") }
                    Text("Withdraw").tag("withdrawn")
                }
                Button(received ? "Decision confirmed" : sending ? "Saving…" : "Confirm reviewed decision") { Task { await submit() } }.disabled(sending || received || explanation.count < 20)
                if failed { Text("Decision not confirmed. Check reviewer independence, sources, and permissions. Refresh the queue before retrying.").foregroundStyle(.red) }
            }
        }.navigationTitle("Reviewed decision").disabled(sending || received)
    }
    @MainActor private func submit() async {
        let session = WhisperReviewSession(); sending = true; failed = false
        nonisolated struct Decision: Encodable, Sendable { let p_report_id: String; let p_explanation: String; let p_sources: [String]; let p_state: String }
        nonisolated struct AppealDecision: Encodable, Sendable { let p_appeal_id: String; let p_explanation: String; let p_sources: [String]; let p_outcome: String }
        let links = sources.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        do {
            try session.check()
            let receipt: UUID
            if let appeal {
                receipt = try await SupabaseService.shared.client.rpc("whisper_review_correction_appeal", params: AppealDecision(p_appeal_id: appeal.id, p_explanation: explanation, p_sources: links, p_outcome: outcome == "active" ? "upheld" : outcome)).execute().value
            } else {
                receipt = try await SupabaseService.shared.client.rpc("whisper_review_correction", params: Decision(p_report_id: report.id, p_explanation: explanation, p_sources: links, p_state: outcome)).execute().value
            }
            try session.check(); _ = receipt; sending = false; received = true
        } catch is CancellationError { } catch { guard session.generation == AccountStorage.generation else { return }; sending = false; failed = true }
    }
}
