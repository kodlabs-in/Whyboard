import Observation
import PencilKit

@MainActor
@Observable
final class InfiniteCanvasController {
  private(set) var zoomPercentage: String
  private(set) var zoomScale: CGFloat
  private(set) var contentOffset: CGPoint

  @ObservationIgnored private weak var canvasView: PKCanvasView?
  @ObservationIgnored private let initialViewport: InfiniteCanvasViewport?
  @ObservationIgnored private var onViewportChanged: ((InfiniteCanvasViewport) -> Void)?

  init(initialViewport: InfiniteCanvasViewport?) {
    self.initialViewport = initialViewport
    let zoomScale = initialViewport?.zoomScale ?? InfiniteCanvasMetrics.defaultZoomScale
    self.zoomPercentage = Self.percentage(for: zoomScale)
    self.zoomScale = zoomScale
    self.contentOffset = initialViewport?.contentOffset ?? .zero
  }

  func configure(onViewportChanged: @escaping (InfiniteCanvasViewport) -> Void) {
    self.onViewportChanged = onViewportChanged
  }

  func attach(_ canvasView: PKCanvasView) {
    guard self.canvasView !== canvasView else { return }
    self.canvasView = canvasView
    applyInitialViewport(to: canvasView)
    syncViewport(from: canvasView)
  }

  func detach(_ canvasView: PKCanvasView) {
    guard self.canvasView === canvasView else { return }
    self.canvasView = nil
  }

  func syncViewport(from canvasView: PKCanvasView) {
    zoomScale = canvasView.zoomScale
    contentOffset = canvasView.contentOffset
    let nextPercentage = Self.percentage(for: canvasView.zoomScale)
    if nextPercentage != zoomPercentage {
      zoomPercentage = nextPercentage
    }
  }

  func zoomIn() {
    zoom(by: 1.25)
  }

  func zoomOut() {
    zoom(by: 0.8)
  }

  func resetView() {
    guard let canvasView else { return }
    canvasView.setZoomScale(InfiniteCanvasMetrics.defaultZoomScale, animated: false)
    canvasView.setContentOffset(centeredOffset(in: canvasView), animated: true)
    syncViewport(from: canvasView)
  }

  var visibleCenter: CGPoint {
    guard let canvasView else {
      return CGPoint(
        x: InfiniteCanvasMetrics.contentSize.width / 2,
        y: InfiniteCanvasMetrics.contentSize.height / 2)
    }
    return CGPoint(
      x: (canvasView.contentOffset.x + canvasView.bounds.width / 2) / canvasView.zoomScale,
      y: (canvasView.contentOffset.y + canvasView.bounds.height / 2) / canvasView.zoomScale)
  }

  func persistCurrentViewport() {
    guard let canvasView else { return }
    onViewportChanged?(
      InfiniteCanvasViewport(
        contentOffset: canvasView.contentOffset,
        zoomScale: canvasView.zoomScale))
  }

  private func applyInitialViewport(to canvasView: PKCanvasView) {
    canvasView.layoutIfNeeded()
    let zoomScale = initialViewport?.zoomScale ?? InfiniteCanvasMetrics.defaultZoomScale
    canvasView.setZoomScale(zoomScale, animated: false)
    let offset = initialViewport?.contentOffset ?? centeredOffset(in: canvasView)
    canvasView.setContentOffset(offset, animated: false)
  }

  private func zoom(by factor: CGFloat) {
    guard let canvasView else { return }
    let targetScale = InfiniteCanvasMetrics.clampedZoomScale(canvasView.zoomScale * factor)
    canvasView.zoom(to: zoomRect(in: canvasView, targetScale: targetScale), animated: true)
  }

  private func zoomRect(in canvasView: PKCanvasView, targetScale: CGFloat) -> CGRect {
    let currentScale = canvasView.zoomScale
    let visibleCenter = CGPoint(
      x: (canvasView.contentOffset.x + canvasView.bounds.width / 2) / currentScale,
      y: (canvasView.contentOffset.y + canvasView.bounds.height / 2) / currentScale)
    let targetSize = CGSize(
      width: canvasView.bounds.width / targetScale,
      height: canvasView.bounds.height / targetScale)
    return CGRect(
      x: visibleCenter.x - targetSize.width / 2,
      y: visibleCenter.y - targetSize.height / 2,
      width: targetSize.width,
      height: targetSize.height)
  }

  private func centeredOffset(in canvasView: PKCanvasView) -> CGPoint {
    CGPoint(
      x: max(0, (canvasView.contentSize.width - canvasView.bounds.width) / 2),
      y: max(0, (canvasView.contentSize.height - canvasView.bounds.height) / 2))
  }

  private static func percentage(for zoomScale: CGFloat) -> String {
    "\(Int((zoomScale * 100).rounded()))%"
  }
}
