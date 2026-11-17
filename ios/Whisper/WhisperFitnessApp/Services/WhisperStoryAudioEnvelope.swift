import AVFoundation

/// Bounded mono envelope for the actual available excerpt, never invented audio peaks.
nonisolated enum WhisperStoryAudioEnvelope {
    static func load(_ url: URL) async -> [Float] {
        // AVAssetReader's synchronous reads must not race cancelReading(). Download first,
        // so cancellation never depends on a network-backed copyNextSampleBuffer finishing.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        var downloaded: URL?
        defer {
            session.invalidateAndCancel()
            if let downloaded { try? FileManager.default.removeItem(at: downloaded) }
        }
        let source: URL
        if url.isFileURL { source = url }
        else {
            guard url.scheme?.lowercased() == "https", !Task.isCancelled else { return [] }
            do {
                let (file, response) = try await session.download(from: url)
                downloaded = file
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !Task.isCancelled else { return [] }
                source = file
            } catch { return [] }
        }
        guard let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 16 * 1024 * 1024, !Task.isCancelled else { return [] }
        let task = Task.detached(priority: .utility) { () -> [Float] in
            let asset = AVURLAsset(url: source)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let reader = try? AVAssetReader(asset: asset), !Task.isCancelled else { return [] }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            guard reader.canAdd(output) else { return [] }
            reader.add(output); reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 60, preferredTimescale: 600))
            guard !Task.isCancelled, reader.startReading() else { return [] }
            // Reader creation, sample reads and cancellation all stay on this one worker.
            defer { if reader.status == .reading { reader.cancelReading() } }
            var peaks: [Float] = []; var peak: Float = 0; var count: Int = 0
            while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                let bytes = CMBlockBufferGetDataLength(block)
                guard bytes > 0, bytes < 4_000_000 else { return [] }
                let copyLength = (bytes / 4) * 4
                var chunk = [Float](repeating: 0, count: bytes / 4)
                let copied = chunk.withUnsafeMutableBytes { raw in
                    guard let base = raw.baseAddress else { return OSStatus(-1) }
                    return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: copyLength, destination: base)
                }
                guard copied == kCMBlockBufferNoErr else { return [] }
                for value in chunk {
                    peak = max(peak, value.isFinite ? abs(value) : 0); count += 1
                    if count == 800 { peaks.append(peak); peak = 0; count = 0 }
                }
                if peaks.count >= 600 { break }
            }
            guard !Task.isCancelled, reader.status != .failed, reader.status != .cancelled else { return [] }
            if count > 0 { peaks.append(peak) }
            let maximum = max(0.001, peaks.max() ?? 0.001)
            return peaks.map { sqrt($0 / maximum) }
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
