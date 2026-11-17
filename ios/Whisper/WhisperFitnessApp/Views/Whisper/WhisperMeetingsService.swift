import Foundation
import Supabase
import SwiftUI

/// Meeting requests — a visitor or member taps "Schedule a call" on a
/// recruiter's featured card and submits their email + preferred time. The
/// recruiter sees the request here and approves (with a Google Meet link) or
/// declines. On approval, the backend sends a Whisper-branded email to the
/// requester with the Meet link.
///
/// Mirrors the web recruiter dashboard's Meetings tab. The recruiter is the
/// only one who reads/decides here; the requester never sees the calendar.
@MainActor
@Observable
final class WhisperMeetingsService {
    static let shared = WhisperMeetingsService()

    private let client = SupabaseService.shared.client
    private var currentUID: String { AccountStorage.currentUserID.lowercased() }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    var requests: [MeetingRow] = []
    var isLoading: Bool = false
    var lastError: String?

    private init() {}

    // MARK: - Row types

    nonisolated struct MeetingRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let recruiter_id: String?
        let recruiter_username: String?
        let featured_id: String?
        let requester_user_id: String?
        let requester_name: String
        let requester_email: String
        let requested_time: String
        let requester_timezone: String?
        let message: String?
        var status: String
        let meeting_link: String?
        let recruiter_note: String?
        let decided_at: String?
        let created_at: String?
    }

    // MARK: - Load

    /// Fetch all meeting requests assigned to the signed-in recruiter.
    func refresh() async {
        guard isRemote else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await client.auth.session.accessToken
            guard let url = URL(string: "\(WhisperBillingBackend.url)/meetings/recruiter") else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastError = "Couldn't load meeting requests."
                return
            }
            struct ListResponse: Codable { let requests: [MeetingRow] }
            let parsed = try JSONDecoder().decode(ListResponse.self, from: data)
            requests = parsed.requests.sorted { a, b in
                if (a.status == "pending") != (b.status == "pending") {
                    return a.status == "pending"
                }
                return (a.created_at ?? "").compare(b.created_at ?? "") == .orderedDescending
            }
            lastError = nil
        } catch {
            lastError = "Couldn't load meeting requests."
            print("[Meetings] refresh error: \(error.localizedDescription)")
        }
    }

    // MARK: - Decide

    /// Approve a request — the recruiter pastes the Google Meet link that will
    /// be emailed to the requester in a Whisper-branded invite.
    func approve(id: String, meetingLink: String, note: String?) async -> Bool {
        guard isRemote else { return false }
        do {
            let token = try await client.auth.session.accessToken
            guard let url = URL(string: "\(WhisperBillingBackend.url)/meetings/decide") else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            var payload: [String: Any] = [
                "id": id,
                "decision": "approved",
                "meetingLink": meetingLink
            ]
            if let note, !note.isEmpty { payload["recruiterNote"] = note }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if ok { await refresh() }
            return ok
        } catch {
            lastError = "Couldn't approve the meeting."
            return false
        }
    }

    /// Decline a request — the requester is notified by email.
    func deny(id: String, note: String?) async -> Bool {
        guard isRemote else { return false }
        do {
            let token = try await client.auth.session.accessToken
            guard let url = URL(string: "\(WhisperBillingBackend.url)/meetings/decide") else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            var payload: [String: Any] = [
                "id": id,
                "decision": "denied"
            ]
            if let note, !note.isEmpty { payload["recruiterNote"] = note }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if ok { await refresh() }
            return ok
        } catch {
            lastError = "Couldn't decline the meeting."
            return false
        }
    }

    // MARK: - Helpers

    var pendingCount: Int { requests.filter { $0.status == "pending" }.count }

    nonisolated static func statusLabel(_ status: String) -> String {
        switch status {
        case "approved": return "Approved"
        case "denied": return "Declined"
        case "cancelled": return "Cancelled"
        default: return "Pending"
        }
    }

    nonisolated static func statusColor(_ status: String) -> Color {
        switch status {
        case "approved": return Color(red: 0.13, green: 0.65, blue: 0.36)
        case "denied": return Color(red: 0.91, green: 0.30, blue: 0.24)
        case "cancelled": return Color(red: 0.42, green: 0.45, blue: 0.50)
        default: return Color(red: 0.93, green: 0.62, blue: 0.16)
        }
    }

    /// Pretty-print the requested_time string (ISO or free-form).
    nonisolated static func formatWhen(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return Self.displayFormatter.string(from: date)
        }
        let alt = ISO8601DateFormatter()
        if let date = alt.date(from: raw) {
            return Self.displayFormatter.string(from: date)
        }
        return raw
    }

    nonisolated static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()
}
