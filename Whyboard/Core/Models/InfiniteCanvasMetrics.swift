import CoreGraphics

enum InfiniteCanvasMetrics {
  static let contentSize = CGSize(width: 16_384, height: 16_384)
  static let minimumZoomScale: CGFloat = 0.2
  static let maximumZoomScale: CGFloat = 5
  static let defaultZoomScale: CGFloat = 1

  static func clampedZoomScale(_ value: CGFloat) -> CGFloat {
    min(max(value, minimumZoomScale), maximumZoomScale)
  }
}
