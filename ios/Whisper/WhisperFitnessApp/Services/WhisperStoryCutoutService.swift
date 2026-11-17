import Foundation
import Vision
import CoreImage
import UIKit

/// Vision work stays off the UI actor. The input is bounded before inference.
nonisolated enum WhisperStoryCutoutService {
    static func makePNG(from data: Data) throws -> Data {
        guard let image = WhisperImageCache.decode(data, maxPixelSize: 1600), let cgImage = image.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw CocoaError(.featureUnsupported) }
        try Task.checkCancellation()
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
        let output = CIImage(cvPixelBuffer: buffer)
        guard let result = CIContext().createCGImage(output, from: output.extent), let png = UIImage(cgImage: result).pngData() else { throw CocoaError(.fileWriteUnknown) }
        return png
    }
}
