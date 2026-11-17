import Foundation

/// Read the installed executable's entitlement slot, not the source plist or
/// provisioning profile (which is only an allowlist). This is a capability
/// preflight, never an authentication or cryptographic signature validator;
/// iOS validates the executable's signature when it installs/launches it.
/// No private Security APIs, receipt heuristics, network, or account data.
enum WhisperSignedEntitlements {
    private static let values: [String: Any]? = load()

    static func permitsCloudKit(container identifier: String) -> Bool {
        guard let values,
              let services = values["com.apple.developer.icloud-services"] as? [String],
              services.contains("CloudKit"),
              let containers = values["com.apple.developer.icloud-container-identifiers"] as? [String] else {
            return false
        }
        return containers.contains(identifier)
    }

    /// Apple's public Mach-O / embedded signature layouts:
    /// xnu/EXTERNAL_HEADERS/mach-o/loader.h and xnu/osfmk/kern/cs_blobs.h.
    /// Device executables for this iOS 18+ target are thinned 64-bit Mach-O.
    /// Unknown/unreadable layouts or missing XML slots fail closed: optional
    /// private iCloud is unavailable, rather than risking a CloudKit exception.
    private static func load() -> [String: Any]? {
        guard let url = Bundle.main.executableURL,
              let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        do {
            let reader = Reader(file: file, length: try file.seekToEnd())
            guard let header = try reader.read(offset: 0, count: 32),
                  word(header, at: 0) == 0xfeedfacf,
                  let commandCount = word(header, at: 16), commandCount <= 4_096,
                  let commandBytes = word(header, at: 20),
                  let commands = try reader.read(offset: 32, count: Int(commandBytes)) else { return nil }
            var offset = 0
            for _ in 0..<commandCount {
                guard let command = word(commands, at: offset),
                      let size = word(commands, at: offset + 4),
                      size >= 8, size % 8 == 0,
                      Int(size) <= commands.count - offset else { return nil }
                if command == 0x1d { // LC_CODE_SIGNATURE / linkedit_data_command
                    guard size >= 16,
                          let signatureOffset = word(commands, at: offset + 8),
                          let signatureSize = word(commands, at: offset + 12),
                          signatureOffset >= 32 + commandBytes,
                          UInt64(signatureOffset) <= reader.length,
                          UInt64(signatureSize) <= reader.length - UInt64(signatureOffset) else { return nil }
                    return try entitlements(reader: reader, offset: UInt64(signatureOffset), size: Int(signatureSize))
                }
                offset += Int(size)
            }
        } catch {
            // Unavailable signing metadata must not prevent normal app entry.
        }
        return nil
    }

    private static func entitlements(reader: Reader, offset: UInt64, size: Int) throws -> [String: Any]? {
        guard size >= 12,
              let header = try reader.read(offset: offset, count: 12),
              word(header, at: 0, bigEndian: true) == 0xfade0cc0,
              let blobLength = word(header, at: 4, bigEndian: true),
              Int(blobLength) <= size, blobLength >= 12,
              let count = word(header, at: 8, bigEndian: true), count <= 1_024 else { return nil }
        let indexLength = 12 + Int(count) * 8
        guard indexLength <= Int(blobLength),
              let index = try reader.read(offset: offset, count: indexLength) else { return nil }
        for entry in 0..<Int(count) {
            let position = 12 + entry * 8
            guard let slot = word(index, at: position, bigEndian: true) else { return nil }
            guard slot == 5 else { continue } // CSSLOT_ENTITLEMENTS
            guard let relative = word(index, at: position + 4, bigEndian: true),
                  Int(relative) >= indexLength,
                  Int(relative) <= Int(blobLength) - 8,
                  let entitlementHeader = try reader.read(offset: offset + UInt64(relative), count: 8),
                  word(entitlementHeader, at: 0, bigEndian: true) == 0xfade7171,
                  let length = word(entitlementHeader, at: 4, bigEndian: true), length > 8,
                  Int(length) <= Int(blobLength) - Int(relative),
                  let payload = try reader.read(offset: offset + UInt64(relative) + 8, count: Int(length) - 8) else { return nil }
            return try PropertyListSerialization.propertyList(from: payload, options: [], format: nil) as? [String: Any]
        }
        return nil
    }

    /// Bytewise loads avoid unaligned pointer access or trusting file offsets.
    private static func word(_ data: Data, at offset: Int, bigEndian: Bool = false) -> UInt32? {
        guard offset >= 0, data.count >= 4, offset <= data.count - 4 else { return nil }
        let a = UInt32(data[offset]), b = UInt32(data[offset + 1])
        let c = UInt32(data[offset + 2]), d = UInt32(data[offset + 3])
        return bigEndian ? (a << 24 | b << 16 | c << 8 | d) : (a | b << 8 | c << 16 | d << 24)
    }

    private struct Reader {
        let file: FileHandle
        let length: UInt64

        func read(offset: UInt64, count: Int) throws -> Data? {
            // Only headers, load commands, indexes and one small plist are read;
            // never map/copy the entire executable or its potentially large signature.
            guard count > 0, count <= 1_048_576, offset <= length,
                  UInt64(count) <= length - offset else { return nil }
            try file.seek(toOffset: offset)
            guard let data = try file.read(upToCount: count), data.count == count else { return nil }
            return data
        }
    }
}
