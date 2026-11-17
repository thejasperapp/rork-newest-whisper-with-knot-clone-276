import Foundation

/// Reads our one-turn SSE protocol without a text-line adapter: empty wire lines
/// are significant. Incomplete EOF is never a terminal event or execution grant.
nonisolated struct WhisperKnotEventFramer: Sendable {
    private(set) var byteCount = 0
    private var line = Data()
    private var payload = Data()
    private var hasData = false
    private var skipLineFeed = false
    private var firstLine = true
    // One complete escaped document proposal can exceed the former 300 KB
    // frame. The independent whole-turn 1 MB bound is unchanged.
    private let maximumFrame = 800_000

    mutating func append(_ byte: UInt8) throws -> Data? {
        byteCount += 1
        guard byteCount <= 1_000_000 else { throw WhisperKnotLiveError.interrupted }
        if skipLineFeed {
            skipLineFeed = false
            if byte == 10 { return nil }
        }
        if byte == 13 {
            skipLineFeed = true
            return try finishLine()
        }
        if byte == 10 { return try finishLine() }
        guard line.count < maximumFrame else { throw WhisperKnotLiveError.interrupted }
        line.append(byte)
        return nil
    }

    private mutating func finishLine() throws -> Data? {
        guard var text = String(data: line, encoding: .utf8) else { throw WhisperKnotLiveError.interrupted }
        line.removeAll(keepingCapacity: true)
        // SSE permits one leading UTF-8 BOM, not replacement of malformed UTF-8.
        if firstLine {
            firstLine = false
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        }
        if text.isEmpty {
            guard hasData else { return nil }
            let completed = payload
            payload = Data(); hasData = false
            return completed
        }
        // Heartbeats and other SSE fields are not JSON events. Our authenticated
        // JSON envelope supplies the version, request identity and sequence.
        guard text == "data" || text.hasPrefix("data:") else { return nil }
        var value: Substring = text == "data" ? ""[...] : text.dropFirst(5)
        if value.first == " " { value = value.dropFirst() }
        let separatorSize = hasData ? 1 : 0
        guard payload.count + separatorSize + value.utf8.count <= maximumFrame else {
            throw WhisperKnotLiveError.interrupted
        }
        if hasData { payload.append(10) }
        payload.append(contentsOf: value.utf8)
        hasData = true
        return nil
    }
}
