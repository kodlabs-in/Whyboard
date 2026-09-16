import Foundation
import ImageIO
import UIKit

nonisolated enum AttachmentImageDecoder {
  static func image(at url: URL, maximumPixelDimension: CGFloat) -> UIImage? {
    guard maximumPixelDimension > 0 else { return nil }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(maximumPixelDimension.rounded(.up)),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image)
  }
}

actor AttachmentImageCache {
  static let shared = AttachmentImageCache()

  private let images = NSCache<NSString, UIImage>()

  init() {
    images.totalCostLimit = 64 * 1_024 * 1_024
  }

  func image(at url: URL, maximumPixelDimension: CGFloat = 2_048) -> UIImage? {
    let cacheKey = "\(url.path)#\(Int(maximumPixelDimension))" as NSString
    if let image = images.object(forKey: cacheKey) { return image }
    guard
      let image = AttachmentImageDecoder.image(
        at: url,
        maximumPixelDimension: maximumPixelDimension)
    else { return nil }
    let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
    images.setObject(image, forKey: cacheKey, cost: cost)
    return image
  }

  func clear() {
    images.removeAllObjects()
  }
}
