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

struct InfiniteCanvasViewport: Equatable {
  let contentOffset: CGPoint
  let zoomScale: CGFloat

  init(contentOffset: CGPoint, zoomScale: CGFloat) {
    self.contentOffset = contentOffset
    self.zoomScale = InfiniteCanvasMetrics.clampedZoomScale(zoomScale)
  }

  init?(storedIn note: Note) {
    guard
      let offsetX = note.canvasOffsetX,
      let offsetY = note.canvasOffsetY,
      let zoomScale = note.canvasZoomScale
    else { return nil }

    self.init(
      contentOffset: CGPoint(x: offsetX, y: offsetY),
      zoomScale: CGFloat(zoomScale))
  }

  func differs(from note: Note) -> Bool {
    let storedViewport = InfiniteCanvasViewport(storedIn: note)
    return storedViewport != self
  }
}
