import SwiftUI
import UIKit
import ImageIO
import os

/// Shared decoded cache. Thumbnail variants never replace full-size viewer images.
nonisolated enum WhisperImageCache {
    private static let store: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 900
        return cache
    }()
    nonisolated(unsafe) private static var inflight: [String: (id: UUID, task: Task<UIImage?, Never>, consumers: Set<UUID>, speculative: Bool)] = [:]
    nonisolated(unsafe) private static var generation: UUID = UUID()
    nonisolated(unsafe) private static var byteRequests: [String: (id: UUID, task: Task<Data?, Never>, consumers: Set<UUID>, speculative: Bool)] = [:]
    private static let lock = NSLock()
    private static let downloads = WhisperImageWorkGate(limit: 6)
    private static let imageJobs = WhisperImageWorkGate(limit: 8)
    private static let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Whisper.image-decode"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    static func key(_ url: URL, maxPixelSize: Int? = nil, fillPixelSize: CGSize? = nil) -> String {
        if let size = fillPixelSize {
            return "fill-\(Int(size.width))x\(Int(size.height))|\(url.absoluteString)"
        }
        return "\(maxPixelSize.map { String(max(1, $0)) } ?? "original")|\(url.absoluteString)"
    }

    static func image(for url: URL, maxPixelSize: Int? = nil, fillPixelSize: CGSize? = nil) -> UIImage? {
        store.object(forKey: key(url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize) as NSString)
    }

    static func store(_ image: UIImage, for url: URL) {
        insert(image, key: key(url))
    }

    private static func insert(_ image: UIImage, key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        store.setObject(image, forKey: key as NSString, cost: max(cost, 1))
    }

    /// Release decoded bitmaps under memory pressure without invalidating the
    /// disk HTTP cache or interrupting visible consumers.
    static func trimDecodedImages() { store.removeAllObjects() }

    static func removeAll() {
        let tasks = lock.withLock {
            generation = UUID()
            let images = inflight.values.map(\.task)
            let transfers = byteRequests.values.map(\.task)
            inflight.removeAll()
            byteRequests.removeAll()
            store.removeAllObjects()
            return (images, transfers)
        }
        // Cancellation handlers can synchronously re-enter this cache.
        // Never cancel while holding its nonrecursive lock.
        tasks.0.forEach { $0.cancel() }
        tasks.1.forEach { $0.cancel() }
    }

    static func decode(_ data: Data, maxPixelSize: Int?, fillPixelSize: CGSize? = nil) -> UIImage? {
        if maxPixelSize != nil || fillPixelSize != nil {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            var limit = maxPixelSize ?? 1536
            if let target = fillPixelSize,
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
               let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
                let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
                let swapped = (5...8).contains(orientation)
                let sourceSize = CGSize(width: swapped ? height.doubleValue : width.doubleValue,
                                        height: swapped ? width.doubleValue : height.doubleValue)
                limit = aspectFillLimit(source: sourceSize, target: target)
            }
            guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, limit)
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: bitmap)
        }
        guard let raw = UIImage(data: data) else { return nil }
        return raw.preparingForDisplay() ?? raw
    }

    /// Account for the crop's short axis; panoramas must not become blurry
    /// square tiles. Bound unusually large decodes to 8 megapixels / 8192px.
    static func aspectFillLimit(source: CGSize, target: CGSize) -> Int {
        guard source.width > 0, source.height > 0, source.width.isFinite, source.height.isFinite,
              target.width.isFinite, target.height.isFinite else { return 1536 }
        let longest = max(source.width, source.height)
        let ratio = longest / min(source.width, source.height)
        let needed = longest * min(1, max(target.width / source.width, target.height / source.height))
        let budget = min(8192, sqrt(8_000_000 * ratio))
        return max(1, Int(ceil(min(needed, budget))))
    }

    /// Warming and all size variants join the same exact-URL transfer. Signed query
    /// parameters remain part of the key; an obsolete epoch cannot start new work.
    private static func bytes(_ url: URL, epoch: UUID, priority: TaskPriority, canRetryForeground: Bool = true) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let key = url.absoluteString
        let consumer = UUID()
        let entry: (id: UUID, task: Task<Data?, Never>, speculative: Bool)? = lock.withLock {
            guard generation == epoch else { return nil }
            if var existing = byteRequests[key] {
                let wasSpeculative = existing.speculative
                existing.consumers.insert(consumer)
                if priority != .utility { existing.speculative = false }
                byteRequests[key] = existing
                return (existing.id, existing.task, wasSpeculative)
            }
            let operation = UUID()
            let task = Task.detached(priority: priority) { () -> Data? in
                defer { lock.withLock { if byteRequests[key]?.id == operation { byteRequests[key] = nil } } }
                guard await downloads.acquire() else { return nil }
                guard !Task.isCancelled, lock.withLock({ generation == epoch }) else {
                    await downloads.release()
                    return nil
                }
                let interval = WhisperPerformance.signposter.beginInterval("ImageTransfer")
                defer { WhisperPerformance.signposter.endInterval("ImageTransfer", interval) }
                var request = URLRequest(url: url)
                request.cachePolicy = .useProtocolCachePolicy
                request.timeoutInterval = 20
                request.allowsConstrainedNetworkAccess = lock.withLock { byteRequests[key]?.speculative == false }
                let result = try? await URLSession.shared.data(for: request)
                await downloads.release()
                guard !Task.isCancelled, lock.withLock({ generation == epoch }),
                      let (data, response) = result else { return nil }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
                return data
            }
            byteRequests[key] = (operation, task, [consumer], priority == .utility)
            return (operation, task, priority == .utility)
        }
        guard let entry else { return nil }
        let result = await withTaskCancellationHandler {
            await entry.task.value
        } onCancel: {
            releaseByteConsumer(key: key, operation: entry.id, consumer: consumer)
        }
        releaseByteConsumer(key: key, operation: entry.id, consumer: consumer)
        guard !Task.isCancelled, lock.withLock({ generation == epoch }) else { return nil }
        // An issued speculative request cannot change its Low Data policy. A
        // visible consumer retries once with foreground policy if that one fails.
        if result == nil, entry.speculative, priority != .utility, canRetryForeground {
            return await bytes(url, epoch: epoch, priority: priority, canRetryForeground: false)
        }
        return result
    }

    private static func releaseByteConsumer(key: String, operation: UUID, consumer: UUID) {
        let abandoned: Task<Data?, Never>? = lock.withLock {
            guard var entry = byteRequests[key], entry.id == operation else { return nil }
            entry.consumers.remove(consumer)
            if entry.consumers.isEmpty {
                byteRequests[key] = nil
                return entry.task
            }
            byteRequests[key] = entry
            return nil
        }
        abandoned?.cancel()
    }

    /// Warm protocol-respecting HTTP bytes and optionally the exact upcoming
    /// card variant. Never decode camera originals speculatively. Low Data Mode
    /// still blocks these utility transfers; foreground loads keep their policy.
    static func prefetch(_ url: URL, fillPixelSize: CGSize? = nil) async {
        guard !Task.isCancelled, !WhisperVideo.isVideo(url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        if let fillPixelSize {
            _ = await loadVariant(url, maxPixelSize: nil, fillPixelSize: fillPixelSize, priority: .utility)
        } else {
            let epoch = lock.withLock { generation }
            _ = await bytes(url, epoch: epoch, priority: .utility)
        }
    }

    private final class DecodeCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.withLock { cancelled = true } }
        var isCancelled: Bool { lock.withLock { cancelled } }
    }

    private static func decodeOffMain(_ data: Data, maxPixelSize: Int?, fillPixelSize: CGSize?, epoch: UUID) async -> UIImage? {
        let cancellation = DecodeCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                decodeQueue.addOperation {
                    guard !cancellation.isCancelled, lock.withLock({ generation == epoch }) else {
                        continuation.resume(returning: nil); return
                    }
                    let interval = WhisperPerformance.Span("ImageDecode")
                    let image = autoreleasepool { decode(data, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize) }
                    let valid = !cancellation.isCancelled && lock.withLock { generation == epoch }
                    interval.finish(completed: valid && image != nil)
                    continuation.resume(returning: valid ? image : nil)
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    /// Identical visible and intentional prefetch variants share work; only the
    /// final departing consumer cancels the decode and its URL-byte subscription.
    static func load(_ url: URL, maxPixelSize: Int? = nil, fillPixelSize: CGSize? = nil) async -> UIImage? {
        await loadVariant(url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize, priority: .userInitiated)
    }

    private static func loadVariant(_ url: URL, maxPixelSize: Int?, fillPixelSize: CGSize?, priority: TaskPriority, canRetryForeground: Bool = true) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let hit = image(for: url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize) { return hit }
        let cacheKey = key(url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize)
        let epoch = lock.withLock { generation }
        let consumer = UUID()
        let entry: (id: UUID, task: Task<UIImage?, Never>, speculative: Bool)? = lock.withLock {
            guard generation == epoch, !Task.isCancelled else { return nil }
            if var existing = inflight[cacheKey] {
                existing.consumers.insert(consumer)
                inflight[cacheKey] = existing
                return (existing.id, existing.task, existing.speculative)
            }
            let operation = UUID()
            let task = Task.detached(priority: priority) { () -> UIImage? in
                defer { lock.withLock { if inflight[cacheKey]?.id == operation { inflight[cacheKey] = nil } } }
                guard await imageJobs.acquire() else { return nil }
                defer { Task { await imageJobs.release() } }
                guard !Task.isCancelled else { return nil }
                guard let data = await bytes(url, epoch: epoch, priority: priority), !Task.isCancelled else { return nil }
                guard let decoded = await decodeOffMain(data, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize, epoch: epoch), !Task.isCancelled else { return nil }
                return lock.withLock {
                    guard generation == epoch, !Task.isCancelled, inflight[cacheKey]?.id == operation else { return nil }
                    insert(decoded, key: cacheKey)
                    return decoded
                }
            }
            inflight[cacheKey] = (operation, task, [consumer], priority == .utility)
            return (operation, task, priority == .utility)
        }
        guard let entry else { return nil }
        // Install after registration: already-cancelled callers invoke onCancel
        // immediately, closing the cancellation-before-registration race.
        let result = await withTaskCancellationHandler {
            await entry.task.value
        } onCancel: {
            releaseVariantConsumer(key: cacheKey, operation: entry.id, consumer: consumer)
        }
        releaseVariantConsumer(key: cacheKey, operation: entry.id, consumer: consumer)
        guard !Task.isCancelled, lock.withLock({ generation == epoch }) else { return nil }
        if result == nil, entry.speculative, priority != .utility, canRetryForeground {
            return await loadVariant(url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize,
                                     priority: priority, canRetryForeground: false)
        }
        return result
    }

    private static func releaseVariantConsumer(key: String, operation: UUID, consumer: UUID) {
        let abandoned: Task<UIImage?, Never>? = lock.withLock {
            guard var entry = inflight[key], entry.id == operation else { return nil }
            entry.consumers.remove(consumer)
            if entry.consumers.isEmpty {
                inflight[key] = nil
                return entry.task
            }
            inflight[key] = entry
            return nil
        }
        // Cancelling re-enters the byte-cache cancellation handler.
        abandoned?.cancel()
    }
}

struct WhisperCachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let maxPixelSize: Int?
    private let fillPixelSize: CGSize?
    private let content: (AsyncImagePhase) -> Content
    @State private var phase: AsyncImagePhase
    @State private var loadedKey: String?

    private var requestKey: String? { url.map { WhisperImageCache.key($0, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize) } }

    init(url: URL?, maxPixelSize: Int? = nil, fillPixelSize: CGSize? = nil, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url; self.maxPixelSize = maxPixelSize; self.fillPixelSize = fillPixelSize; self.content = content
        if let url, let cached = WhisperImageCache.image(for: url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
            _loadedKey = State(initialValue: WhisperImageCache.key(url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize))
        } else {
            _phase = State(initialValue: .empty)
            _loadedKey = State(initialValue: nil)
        }
    }

    init<I: View, P: View>(url: URL?, maxPixelSize: Int? = nil,
                          @ViewBuilder content: @escaping (Image) -> I,
                          @ViewBuilder placeholder: @escaping () -> P) where Content == AnyView {
        self.init(url: url, maxPixelSize: maxPixelSize) { (phase: AsyncImagePhase) -> AnyView in
            if case .success(let image) = phase { return AnyView(content(image)) }
            return AnyView(placeholder())
        }
    }

    private var displayedPhase: AsyncImagePhase {
        if loadedKey == requestKey { return phase }
        if let url, let cached = WhisperImageCache.image(for: url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize) {
            return .success(Image(uiImage: cached))
        }
        return .empty
    }

    var body: some View {
        content(displayedPhase)
            .task(id: requestKey) {
                guard let url else { phase = .empty; loadedKey = nil; return }
                let key = requestKey
                if loadedKey == key, case .success = phase { return }
                if let cached = WhisperImageCache.image(for: url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize) {
                    phase = .success(Image(uiImage: cached)); loadedKey = key
                    return
                }
                phase = .empty; loadedKey = key
                let image = await WhisperImageCache.load(url, maxPixelSize: maxPixelSize, fillPixelSize: fillPixelSize)
                guard !Task.isCancelled else { return }
                if let image { phase = .success(Image(uiImage: image)) }
                else { phase = .failure(URLError(.cannotDecodeContentData)) }
            }
    }
}
