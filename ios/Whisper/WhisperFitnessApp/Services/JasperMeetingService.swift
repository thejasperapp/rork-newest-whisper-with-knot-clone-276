import Foundation
import Supabase

@MainActor enum JasperMeetingService {
    static let baseURL = Config.allValues["EXPO_PUBLIC_JASPER_MEETINGS_URL"] ?? "https://e1p9ya2tdy09t3sy62x1s-backend.rork.app"

    static func request<T: Decodable>(_ path: String, owner: String, body: [String: Any]? = nil) async throws -> T {
        let generation = AccountStorage.generation
        let session = try await SupabaseService.shared.client.auth.session
        try Task.checkCancellation()
        guard generation == AccountStorage.generation, session.user.id.uuidString.lowercased() == owner.lowercased(), AccountStorage.currentUserID.lowercased() == owner.lowercased() else { throw WhisperNotebookError.accountChanged }
        guard let url = URL(string: "\(baseURL)/jasper-meetings/\(path)") else { throw WhisperNotebookError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "X-Whisper-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard generation == AccountStorage.generation, AccountStorage.currentUserID.lowercased() == owner.lowercased() else { throw WhisperNotebookError.accountChanged }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "request_failed"
            throw JasperMeetingFailure(code: code)
        }
        guard data.count < 2000000 else { throw WhisperNotebookError.tooLong }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
