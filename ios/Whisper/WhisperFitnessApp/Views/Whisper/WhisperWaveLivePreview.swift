import SwiftUI
import AVFoundation
import CoreImage

struct WhisperWaveLivePreview: UIViewRepresentable {
    let camera: SnapCameraSession
    let configuration: WhisperWaveLiveFrameRenderer.Configuration
    let photo: CIImage?
    let video: WhisperWaveLiveVideoBackground?
    let preparedURL: URL?
    let onStatus: @MainActor (String?) -> Void
    var onCatalogFrame: @MainActor (CGImage) -> Void = { _ in }
    var fillsFrame: Bool = false
    var onFrameTime: @MainActor (Double) -> Void = { _ in }
    var consumerID: String = "camera"

    final class Coordinator {
        let renderer = WhisperWaveLiveFrameRenderer()
        let subscriptionID: UUID = UUID()
        weak var camera: SnapCameraSession?
        var lastConfiguration: WhisperWaveLiveFrameRenderer.Configuration?
        var lastURL: URL?
        var lastPhoto: CIImage?
        var lastVideo: WhisperWaveLiveVideoBackground?
        var consumerID: String?
        var displayedEpoch: UUID?
        var deliveryID: UUID = UUID()
        var waitingForFrame: Bool = true
        var lastIssue: String? = "Starting camera"
        let accountGeneration = AccountStorage.generation
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.clipsToBounds = true
        context.coordinator.camera = camera
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        let coordinator = context.coordinator
        view.contentMode = fillsFrame ? .scaleAspectFill : .scaleAspectFit
        let renderingChanged = coordinator.consumerID != consumerID || coordinator.lastConfiguration?.hasSameRendering(as: configuration) != true || coordinator.lastURL != preparedURL || coordinator.lastPhoto !== photo || coordinator.lastVideo !== video
        if renderingChanged {
            coordinator.consumerID = consumerID
            coordinator.deliveryID = UUID()
            coordinator.waitingForFrame = true
            let deliveryID = coordinator.deliveryID
            // Defer SwiftUI state changes out of updateUIView; a new frame can
            // satisfy readiness first, in which case this notice is obsolete.
            Task { @MainActor [weak coordinator] in
                guard let coordinator, coordinator.deliveryID == deliveryID, coordinator.waitingForFrame,
                      coordinator.accountGeneration == AccountStorage.generation else { return }
                coordinator.lastIssue = "Updating camera effect"
                onStatus(coordinator.lastIssue)
            }
        }
        if coordinator.lastConfiguration != configuration || coordinator.lastURL != preparedURL || coordinator.lastPhoto !== photo || coordinator.lastVideo !== video {
            coordinator.renderer.configure(configuration, photo: photo, video: video, preparedURL: preparedURL)
            if coordinator.lastConfiguration?.background != configuration.background { view.image = nil }
            coordinator.lastConfiguration = configuration; coordinator.lastURL = preparedURL
            coordinator.lastPhoto = photo; coordinator.lastVideo = video
        }
        let renderer = coordinator.renderer
        let tap = camera.frameTap
        let deliveryID = coordinator.deliveryID
        camera.frameTap.installWaveHandler(owner: coordinator.subscriptionID) { [weak view, weak coordinator] buffer, time, orientation in
            let sourceEpoch = tap.sourceEpoch
            renderer.render(buffer, at: time, orientation: orientation, sourceEpoch: sourceEpoch, recordingOrigin: tap.recordingOrigin, isSourceCurrent: { tap.sourceEpoch == sourceEpoch }) { image, issue, snapshot, elapsed in
                guard let view, let coordinator, coordinator.deliveryID == deliveryID,
                      coordinator.accountGeneration == AccountStorage.generation, tap.sourceEpoch == sourceEpoch else { return }
                let wasWaiting = coordinator.waitingForFrame
                coordinator.waitingForFrame = false
                if coordinator.displayedEpoch != sourceEpoch { view.image = nil }
                coordinator.displayedEpoch = sourceEpoch
                if let image { view.image = UIImage(cgImage: image); onFrameTime(elapsed) }
                else { view.image = nil }
                if let snapshot { onCatalogFrame(snapshot) }
                if wasWaiting || coordinator.lastIssue != issue {
                    coordinator.lastIssue = issue
                    onStatus(issue)
                }
            }
        }
    }
    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        coordinator.renderer.invalidate()
        coordinator.deliveryID = UUID()
        coordinator.waitingForFrame = false
        coordinator.camera?.frameTap.removeWaveHandler(owner: coordinator.subscriptionID)
        view.image = nil
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
