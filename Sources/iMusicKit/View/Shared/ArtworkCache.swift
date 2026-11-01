import ImageIO
import SwiftUI

final class ArtworkCache: @unchecked Sendable {
    /// Process-wide thumbnail cache shared by artwork views.
    static let shared = ArtworkCache()
    /// Cost-limited decoded image cache keyed by file path and requested thumbnail size.
    let cache = NSCache<NSString, ImageBox>()
    init() { cache.totalCostLimit = 32 * 1_024 * 1_024 }
    final class ImageBox {
        /// Decoded thumbnail wrapped in an object so NSCache can retain and evict it.
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
    /// Returns a decoded thumbnail from memory without inspecting or decoding its source file.
    func cachedImage(at url: URL, size: Int) -> CGImage? {
        cache.object(forKey: key(for: url, size: size))?.image
    }
    /// Returns a cached thumbnail or reads and decodes its source; call off the main actor.
    func image(at url: URL, size: Int) -> CGImage? {
        if let image = cachedImage(at: url, size: size) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
            )
        else { return nil }
        // Embedded covers can carry grayscale, CMYK, or high-bit-depth color data. Materialize
        // the thumbnail before handing it to SwiftUI's scaled, clipped player artwork layer.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let decoded = context.makeImage() else { return nil }
        cache.setObject(
            ImageBox(decoded),
            forKey: key(for: url, size: size),
            cost: decoded.bytesPerRow * decoded.height
        )
        return decoded
    }

    /// Uses the owning library path and thumbnail resolution for both cache access paths.
    private func key(for url: URL, size: Int) -> NSString {
        "\(url.path)#\(size)" as NSString
    }
}
