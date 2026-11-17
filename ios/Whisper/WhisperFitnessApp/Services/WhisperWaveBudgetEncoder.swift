import AVFoundation
import AudioToolbox
import Foundation

/// Owns decoding and encoding off the UI actor. Reads the shared composed
/// frames/audio at their original timestamps; no file-length truncation.
actor WhisperWaveBudgetEncoder {
    func encode(asset: AVAsset, video: AVVideoComposition, audio: AVAudioMix?, progress: @escaping @Sendable (String, Double?) async -> Void) async throws -> URL {
        let duration = try await asset.load(.duration)
        guard WhisperWaveUploadPolicy.accepts(duration: duration.seconds) else {
            throw failure("Waves can be up to 6 minutes after trimming and speed changes. Your clips are unchanged.")
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw failure("No video track could be read. Reopen Clips and retry.") }
        var audioTracks: [AVAssetTrack] = []
        var audioRanges: [CMTimeRange] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            let segments = try await track.load(.segments)
            let occupied = segments.filter { !$0.isEmpty }.map { $0.timeMapping.target }
            if !occupied.isEmpty {
                audioTracks.append(track)
                audioRanges.append(contentsOf: occupied)
            }
        }
        let rate = WhisperWaveUploadPolicy.videoBitRate(duration: duration.seconds, hasAudio: !audioTracks.isEmpty)
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("wave-final-\(UUID().uuidString).mp4")
            var keep = false
            defer { if !keep { try? FileManager.default.removeItem(at: output) } }
            let adjustedRate = attempt == 0 ? rate : Int(Double(rate) * 0.72)
            await progress(attempt == 0 ? "Rendering wave" : "Optimizing upload size", 0)
            try await write(asset: asset, video: video, audio: audio, videoTracks: videoTracks, audioTracks: audioTracks, audioRanges: audioRanges, duration: duration, bitRate: adjustedRate, output: output, progress: progress)
            await progress("Checking finished video", nil)
            let finished = AVURLAsset(url: output)
            let actualDuration = try await finished.load(.duration)
            let finishedTracks = try await finished.loadTracks(withMediaType: .video)
            guard let track = finishedTracks.first else { throw failure("The rendered video has no picture. Your edit is safe; please retry.") }
            let coverage = try await track.load(.timeRange)
            let tolerance = WhisperWaveUploadPolicy.durationTolerance
            guard actualDuration.seconds.isFinite,
                  abs(actualDuration.seconds - duration.seconds) <= tolerance,
                  abs(coverage.start.seconds) <= tolerance,
                  abs(coverage.end.seconds - duration.seconds) <= tolerance else {
                throw failure("The render ended before all your footage was ready. Nothing was uploaded. Please retry.")
            }
            if !audioTracks.isEmpty {
                let finishedAudio = try await finished.loadTracks(withMediaType: .audio)
                guard let audioTrack = finishedAudio.first else { throw failure("The audio mix was missing from the render. Nothing was uploaded. Please retry.") }
                let audioCoverage = try await audioTrack.load(.timeRange)
                guard audioRanges.allSatisfy({ range in
                    audioCoverage.start.seconds <= range.start.seconds + tolerance && audioCoverage.end.seconds >= min(duration.seconds, range.end.seconds) - tolerance
                }) else { throw failure("The audio mix ended early. Nothing was uploaded. Please retry.") }
            }
            let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0 else { throw failure("The video file couldn't be verified. Please retry.") }
            if bytes < WhisperWaveUploadPolicy.maximumBytes {
                try Task.checkCancellation()
                keep = true
                return output
            }
        }
        throw failure("The full video couldn't fit the upload budget. Your original clips and edits are safe. Please retry the render.")
    }

    private func write(asset: AVAsset, video: AVVideoComposition, audio: AVAudioMix?, videoTracks: [AVAssetTrack], audioTracks: [AVAssetTrack], audioRanges: [CMTimeRange], duration: CMTime, bitRate: Int, output: URL, progress: @escaping @Sendable (String, Double?) async -> Void) async throws {
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        var completed = false
        defer {
            if !completed { reader.cancelReading(); writer.cancelWriting() }
        }
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        writer.shouldOptimizeForNetworkUse = true
        guard let composition = video.mutableCopy() as? AVMutableVideoComposition else { throw failure("The edit couldn't be prepared for export.") }
        // The compositor keeps its 1080p logical coordinates and scales its
        // final frame to this output size, including text and captions.
        let width = bitRate < 2_500_000 ? 720 : 1080
        let height = width * 16 / 9
        composition.renderSize = CGSize(width: width, height: height)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        videoOutput.videoComposition = composition
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalDurationKey: 2.0
            ]
        ])
        var lanes: [(source: AVAssetReaderOutput, destination: AVAssetWriterInput)] = [(videoOutput, videoInput)]
        if !audioTracks.isEmpty {
            let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false
            ])
            audioOutput.audioMix = audio
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: WhisperWaveUploadPolicy.audioBitRate
            ])
            lanes.append((audioOutput, audioInput))
        }
        for lane in lanes {
            guard reader.canAdd(lane.source), writer.canAdd(lane.destination),
                  writer.canApply(outputSettings: lane.destination.outputSettings, forMediaType: lane.destination.mediaType) else {
                throw failure("This device couldn't configure the video encoder. Your edit is safe.")
            }
            lane.source.alwaysCopiesSampleData = false
            lane.destination.expectsMediaDataInRealTime = false
            reader.add(lane.source)
            writer.add(lane.destination)
        }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? failure("Video rendering couldn't start.") }
            writer.startSession(atSourceTime: .zero)
            try await pump(reader: reader, writer: writer, lanes: lanes, audioRanges: audioRanges, duration: duration, progress: progress)
        } onCancel: {
            // These cancellation APIs unblock pending decode/finalization;
            // scheduling onto this actor would wait behind the blocked read.
            reader.cancelReading()
            writer.cancelWriting()
        }
        completed = true
    }

    private func pump(reader: AVAssetReader, writer: AVAssetWriter, lanes: [(source: AVAssetReaderOutput, destination: AVAssetWriterInput)], audioRanges: [CMTimeRange], duration: CMTime, progress: @escaping @Sendable (String, Double?) async -> Void) async throws {
        var ended: Set<Int> = []
        var audioEnd: Double = 0
        var lastVideoTime: Double = -1
        var lastProgress = Date.distantPast
        var lastActivity = Date()
        while ended.count < lanes.count {
            try Task.checkCancellation()
            guard writer.status == .writing, reader.status == .reading || reader.status == .completed else {
                throw writer.error ?? reader.error ?? failure("Video rendering stopped. Your edit is safe; please retry.")
            }
            var advanced = false
            for (index, lane) in lanes.enumerated() where !ended.contains(index) && lane.destination.isReadyForMoreMediaData {
                try autoreleasepool {
                    guard let sample = lane.source.copyNextSampleBuffer() else {
                        guard reader.status != .failed, reader.status != .cancelled else { throw reader.error ?? failure("A clip couldn't finish decoding.") }
                        lane.destination.markAsFinished()
                        ended.insert(index)
                        advanced = true
                        return
                    }
                    let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if index == 0 {
                        guard seconds.isFinite, seconds >= 0,
                              (lastVideoTime < 0 ? seconds <= 0.1 : seconds > lastVideoTime && seconds - lastVideoTime <= 0.1) else {
                            throw failure("Some video frames were missing. Your clips are unchanged; please retry.")
                        }
                        lastVideoTime = seconds
                    } else {
                        let sampleDuration = CMSampleBufferGetDuration(sample).seconds
                        guard seconds.isFinite, sampleDuration.isFinite, sampleDuration > 0 else {
                            throw failure("An audio segment couldn't be verified. Nothing was uploaded.")
                        }
                        if seconds > audioEnd + 0.1, audioRanges.contains(where: {
                            min(seconds, $0.end.seconds) - max(audioEnd, $0.start.seconds) > 0.1
                        }) {
                            throw failure("Part of the audio mix was missing. Nothing was uploaded. Please retry.")
                        }
                        audioEnd = max(audioEnd, seconds + sampleDuration)
                    }
                    try Task.checkCancellation()
                    guard lane.destination.append(sample) else { throw writer.error ?? failure("A video or audio frame couldn't be encoded.") }
                    advanced = true
                }
            }
            if Date().timeIntervalSince(lastProgress) >= 0.25 {
                lastProgress = Date()
                await progress("Rendering wave", min(0.99, max(0, lastVideoTime / duration.seconds)))
            }
            if advanced { lastActivity = Date() } else {
                guard Date().timeIntervalSince(lastActivity) < 60 else { throw failure("The video encoder stopped responding. Please retry; your edit is safe.") }
                // Backpressure on this actor, never a blocking wait on the UI.
                try await Task.sleep(for: .milliseconds(3))
            }
        }
        guard reader.status == .completed, lastVideoTime + 1.0 / 30 >= duration.seconds - 0.1 else {
            throw reader.error ?? failure("The render didn't include the end of your footage. Nothing was uploaded.")
        }
        guard audioRanges.allSatisfy({ audioEnd >= min(duration.seconds, $0.end.seconds) - 0.1 }) else {
            throw failure("The audio mix didn't finish rendering. Nothing was uploaded. Please retry.")
        }
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? failure("The video couldn't finish saving. Free some device storage and retry.") }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "WhisperWaveEdit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
