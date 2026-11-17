import CoreImage
import Foundation

/// Non-destructive controls shared by the player, cover generator and final export.
nonisolated struct WhisperWaveColorAdjustments: Codable, Equatable, Sendable {
    var intensity: Double = 1
    var exposure: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var warmth: Double = 0

    func process(_ source: CIImage, filter: SnapFilter) -> CIImage {
        var image = source
        if filter != .none, intensity > 0 {
            let styled = filter.process(source)
            image = styled.applyingFilter("CIDissolveTransition", parameters: [
                "inputTargetImage": source, "inputTime": 1 - min(1, max(0, intensity))
            ])
        }
        if exposure != 0 { image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": min(2, max(-2, exposure))]) }
        if contrast != 1 || saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                "inputContrast": min(1.5, max(0.5, contrast)), "inputSaturation": min(2, max(0, saturation))
            ])
        }
        if warmth != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 + min(1, max(-1, warmth)) * 1800, y: 0)
            ])
        }
        return image.cropped(to: source.extent)
    }
}
