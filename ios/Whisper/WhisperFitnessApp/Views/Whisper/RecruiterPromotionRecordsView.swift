import SwiftUI

struct RecruiterPromotionRecordsView: View {
    nonisolated struct Records: Decodable, Sendable {
        struct Record: Decodable, Identifiable, Sendable { let id: String; let promoted_username: String; let role: String; let created_at: String }
        let peopleCount: Int
        let recordCount: Int
        let records: [Record]
    }
    @State private var owner: String = AccountStorage.currentUserID.lowercased()
    @State private var month: Date = Date()
    @State private var result: Records?
    @State private var errorText: String?
    private var period: String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: month)
    }
    var body: some View {
        DisclosureGroup("Recorded promotion totals") {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker("Choose month (UTC)", selection: $month, displayedComponents: .date)
                if let result {
                    Text("\(result.peopleCount) people · \(result.recordCount) recorded role promotions").font(.subheadline.bold())
                    Text("Your promotion ledger, not meeting claims or contracts. If a meeting gives a different number, compare its period and these records. Nothing is silently changed.").font(.caption).foregroundStyle(.secondary)
                    ForEach(result.records.prefix(100)) { row in Text("@\(row.promoted_username) · \(row.role) · \(WhisperBackendService.parseISO(row.created_at)?.formatted(date: .abbreviated, time: .omitted) ?? row.created_at)").font(.caption) }
                    if result.records.count > 100 { Text("Showing the first 100 records; totals include all records for this month.").font(.caption) }
                } else if let errorText { Text(errorText).font(.caption).foregroundStyle(.red); Button("Retry") { Task { await load() } } }
                else { ProgressView() }
            }.padding(.top, 10)
        }.task(id: period) { await load() }
    }
    private func load() async {
        result = nil; errorText = nil
        do {
            let loaded: Records = try await JasperMeetingService.request("clients/promotions?period=\(period)", owner: owner)
            guard owner == AccountStorage.currentUserID.lowercased(), !Task.isCancelled else { return }
            result = loaded
        } catch { if !Task.isCancelled { errorText = error.localizedDescription } }
    }
}
