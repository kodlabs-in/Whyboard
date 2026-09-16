import CoreGraphics

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
