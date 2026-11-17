import SwiftUI
import UIKit
import ImageIO

struct AnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        context.coordinator.imageView = imageView
        context.coordinator.loadGIF(from: url)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var imageView: UIImageView?
        private var loadTask: URLSessionDataTask?

        func loadGIF(from url: URL) {
            loadTask?.cancel()
            loadTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let self, let imageView = self.imageView else { return }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
                let count = CGImageSourceGetCount(source)
                guard count > 1 else {
                    if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                        let img = UIImage(cgImage: cgImage)
                        DispatchQueue.main.async {
                            imageView.image = img
                        }
                    }
                    return
                }

                var images: [UIImage] = []
                var totalDuration: Double = 0

                for i in 0..<count {
                    guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                    images.append(UIImage(cgImage: cgImage))

                    if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                       let gifProps = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                        if let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double, delay > 0 {
                            totalDuration += delay
                        } else if let delay = gifProps[kCGImagePropertyGIFDelayTime] as? Double {
                            totalDuration += delay
                        } else {
                            totalDuration += 0.1
                        }
                    } else {
                        totalDuration += 0.1
                    }
                }

                guard !images.isEmpty else { return }

                DispatchQueue.main.async {
                    imageView.animationImages = images
                    imageView.animationDuration = totalDuration
                    imageView.animationRepeatCount = 0
                    imageView.startAnimating()
                }
            }
            loadTask?.resume()
        }

        deinit {
            loadTask?.cancel()
        }
    }
}
