import ImageIO
import UIKit

/// Downsampled decoding, off the main actor. Three call sites needed the same thing:
/// a full-size phone photo is tens of megabytes and, decoded on the main thread, a
/// visible stall while the grid scrolls.
enum ImageDecoder {
    static func image(from data: Data, maxPixels: Int) async -> UIImage? {
        let pixels = max(1, maxPixels)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: pixels
                      ] as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(cgImage: cg))
            }
        }
    }
}
