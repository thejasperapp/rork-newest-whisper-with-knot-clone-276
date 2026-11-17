import Foundation

/// Foreground, bounded-memory TUS transfer. A retry reconciles the server offset before sending more bytes.
actor WhisperWaveUploadService {
    private var uploadURL: URL?
    private var fileURL: URL?
    private var objectPath: String?
    private var isUploading: Bool = false
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func upload(file: URL, path: String, endpoint: URL, contentType: String = "video/mp4", bucket: String = "whisper-media", token: @escaping @MainActor @Sendable () async throws -> String, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard !isUploading else { throw failure(409) }
        isUploading = true
        defer { isUploading = false }
        try Task.checkCancellation()
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { throw CocoaError(.fileReadCorruptFile) }
        guard size < WhisperWaveUploadPolicy.maximumBytes else { throw failure(413) }
        let identity = "\(endpoint.absoluteString)|\(bucket)|\(path)|\(contentType)|\(size)"
        if fileURL != file || objectPath != identity { uploadURL = nil; fileURL = file; objectPath = identity }
        var creationFailures = 0
        while uploadURL == nil {
            do {
                var create = try await request(endpoint, method: "POST", token: token)
                create.setValue(String(size), forHTTPHeaderField: "Upload-Length")
                let metadata = ["bucketName": bucket, "objectName": path, "contentType": contentType, "cacheControl": "3600"]
                    .sorted { $0.key < $1.key }.map { "\($0.key) \(Data($0.value.utf8).base64EncodedString())" }.joined(separator: ",")
                create.setValue(metadata, forHTTPHeaderField: "Upload-Metadata")
                let (_, response) = try await session.data(for: create)
                guard let http = response as? HTTPURLResponse, http.statusCode == 201,
                      let location = http.value(forHTTPHeaderField: "Location"),
                      let locationURL = URL(string: location, relativeTo: endpoint)?.absoluteURL,
                      locationURL.scheme == "https", locationURL.host == endpoint.host,
                      locationURL.user == nil, locationURL.password == nil else {
                    throw failure((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                uploadURL = locationURL
            } catch {
                try Task.checkCancellation()
                guard retryable(error), creationFailures < 3 else { throw error }
                creationFailures += 1
                try await Task.sleep(for: .seconds(Double(creationFailures * 2)))
            }
        }
        guard let uploadURL else { throw failure(0) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var failures = 0
        var acknowledgedOffset: Int? = nil
        while true {
            try Task.checkCancellation()
            do {
                // HEAD is needed on entry/recovery, not after every successfully acknowledged PATCH.
                if acknowledgedOffset == nil {
                    let head = try await request(uploadURL, method: "HEAD", token: token)
                    let (_, response) = try await session.data(for: head)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                          let raw = http.value(forHTTPHeaderField: "Upload-Offset"), let offset = Int(raw), offset >= 0, offset <= size else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if status == 404 || status == 410 { self.uploadURL = nil }
                        throw failure(status)
                    }
                    acknowledgedOffset = offset
                }
                guard let offset = acknowledgedOffset else { throw failure(0) }
                await progress(Double(offset) / Double(size))
                if offset == size { return }
                try handle.seek(toOffset: UInt64(offset))
                guard let chunk = try handle.read(upToCount: min(6 * 1024 * 1024, size - offset)), !chunk.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                var patch = try await request(uploadURL, method: "PATCH", token: token)
                patch.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
                patch.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
                let (_, patched) = try await session.upload(for: patch, from: chunk)
                guard let ack = patched as? HTTPURLResponse, ack.statusCode == 204,
                      let rawOffset = ack.value(forHTTPHeaderField: "Upload-Offset"), let acknowledged = Int(rawOffset), acknowledged == offset + chunk.count else {
                    throw failure((patched as? HTTPURLResponse)?.statusCode ?? 0)
                }
                failures = 0
                acknowledgedOffset = acknowledged
                await progress(Double(acknowledged) / Double(size))
                if acknowledged == size { return }
            } catch {
                try Task.checkCancellation()
                acknowledgedOffset = nil
                guard retryable(error), failures < 3 else { throw error }
                failures += 1
                try await Task.sleep(for: .seconds(Double(failures * 2)))
            }
        }
    }

    private func retryable(_ error: Error) -> Bool {
        let ns = error as NSError
        return (ns.domain == NSURLErrorDomain && ns.code != NSURLErrorCancelled)
            || (ns.domain == "WaveUpload" && (ns.code == 409 || ns.code == 429 || ns.code >= 500))
    }

    private func request(_ url: URL, method: String, token: @MainActor @Sendable () async throws -> String) async throws -> URLRequest {
        let accessToken = try await token()
        try Task.checkCancellation()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        return request
    }

    private func failure(_ status: Int) -> NSError {
        let message: String
        switch status {
        case 401: message = "Your sign-in expired. Save your draft, sign in again, then retry."
        case 403: message = "Video upload permission was denied. Your edit is safe; please try again after signing in."
        case 413: message = "Choose a video under 50 MiB. Your original footage has not been shortened or deleted."
        case 404, 410: message = "The upload session expired. Retry to start a fresh upload."
        default: message = "Video upload stopped. Check your connection and retry."
        }
        return NSError(domain: "WaveUpload", code: status, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
