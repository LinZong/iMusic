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
  func image(at url: URL, size: Int) -> CGImage? {
    let key = (url.path + String(size)) as NSString
    if let image = cache.object(forKey: key) { return image.image }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: size,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    else { return nil }
    cache.setObject(ImageBox(image), forKey: key, cost: image.bytesPerRow * image.height)
    return image
  }
}
