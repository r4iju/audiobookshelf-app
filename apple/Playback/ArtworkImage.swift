import ImageIO
import UIKit

/// Decode bounded, display-ready pixels away from the UI thread. Serial decoding bounds temporary memory.
enum ArtworkImage {
    private static let decoder = DispatchQueue(label: "loft.artwork.decode", qos: .userInitiated)
    #if os(tvOS)
    static let maximumPixelDimension = 1024
    #else
    static let maximumPixelDimension = 1200
    #endif

    static func decode(_ data: Data, maximumPixelDimension: Int = ArtworkImage.maximumPixelDimension) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let image: UIImage? = await withCheckedContinuation { continuation in
            decoder.async {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    continuation.resume(returning: nil); return
                }
                continuation.resume(returning: UIImage(cgImage: pixels))
            }
        }
        return Task.isCancelled ? nil : image
    }

    static func memoryCost(_ image: UIImage) -> Int {
        guard let pixels = image.cgImage else { return 0 }
        return pixels.bytesPerRow * pixels.height
    }
}
