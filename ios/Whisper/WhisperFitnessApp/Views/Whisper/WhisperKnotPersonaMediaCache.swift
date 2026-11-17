import Foundation
import CryptoKit

/// Display bytes only. Callers must first authorize the immutable ID against a
/// fresh account snapshot. This cache stores no session, consent or approval.
@MainActor final class WhisperKnotPersonaMediaCache {
    static let shared = WhisperKnotPersonaMediaCache()
    private let root: URL
    private let maximumBytes: Int
    init(root: URL? = nil, maximumBytes: Int = 64_000_000) {
        self.root = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("KnotPrivateMedia-v1", isDirectory: true)
        self.maximumBytes = maximumBytes
    }
    private func key(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func directory(_ owner: String) -> URL { root.appendingPathComponent(key(owner.lowercased()), isDirectory: true) }
    func file(owner: String, id: String) -> URL? {
        let url = directory(owner).appendingPathComponent(key(id) + ".mp4")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(date) < 7 * 86400 else { try? FileManager.default.removeItem(at: url); return nil }
        return url
    }
    func store(_ data: Data, owner: String, id: String) throws -> URL {
        guard !data.isEmpty, data.count <= min(maximumBytes, 12_500_000) else { throw CocoaError(.fileWriteOutOfSpace) }
        let directory = directory(owner)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
        let url = directory.appendingPathComponent(key(id) + ".mp4")
        if let previous = try? Data(contentsOf: url), previous != data { throw CocoaError(.fileWriteFileExists) }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let entries = files.compactMap { file -> (URL, Int, Date)? in
            guard let v = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (file, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where entry.0 != url {
            if total > maximumBytes || Date().timeIntervalSince(entry.2) >= 7 * 86400 {
                try FileManager.default.removeItem(at: entry.0); total -= entry.1
            }
        }
        return url
    }
    func clear(owner: String) { try? FileManager.default.removeItem(at: directory(owner)) }
}
