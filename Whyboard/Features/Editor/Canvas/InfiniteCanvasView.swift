import PencilKit
import SwiftUI
import UIKit

struct InfiniteCanvasView: UIViewRepresentable {
  let drawing: PKDrawing
  let drawingRevision: Int
  let drawsWithFinger: Bool
  let isDrawingEnabled: Bool
  let canvasController: InfiniteCanvasController
  let toolPickerController: ToolPickerController
  let onDrawingChanged: (PKDrawing) -> Void
  let onDrawingChangeCommitted: (PKDrawing, PKCanvasView) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      canvasController: canvasController,
      toolPickerController: toolPickerController,
      onDrawingChanged: onDrawingChanged,
      onDrawingChangeCommitted: onDrawingChangeCommitted)
  }

  func makeUIView(context: Context) -> InfiniteCanvasHostView {
    let hostView = InfiniteCanvasHostView()
    let canvasView = hostView.canvasView
    configure(canvasView)
    context.coordinator.apply(drawing, revision: drawingRevision, to: canvasView)
    canvasView.delegate = context.coordinator
    hostView.onAttachedToWindow = { [weak canvasView, weak coordinator = context.coordinator] in
      guard let canvasView, let coordinator else { return }
      coordinator.register(canvasView)
    }
    return hostView
  }

  func updateUIView(_ hostView: InfiniteCanvasHostView, context: Context) {
    context.coordinator.update(
      onDrawingChanged: onDrawingChanged,
      onDrawingChangeCommitted: onDrawingChangeCommitted)
    let canvasView = hostView.canvasView
    canvasView.backgroundColor = .clear
    canvasView.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly
    canvasView.drawingGestureRecognizer.isEnabled = isDrawingEnabled
    if context.coordinator.appliedDrawingRevision != drawingRevision {
      context.coordinator.apply(drawing, revision: drawingRevision, to: canvasView)
    }
  }

  static func dismantleUIView(_ hostView: InfiniteCanvasHostView, coordinator: Coordinator) {
    coordinator.unregister(hostView.canvasView)
    hostView.canvasView.delegate = nil
  }

  private func configure(_ canvasView: PKCanvasView) {
    canvasView.backgroundColor = .clear
    canvasView.isOpaque = false
    canvasView.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly
    canvasView.drawingGestureRecognizer.isEnabled = isDrawingEnabled
    canvasView.contentSize = InfiniteCanvasMetrics.contentSize
    canvasView.minimumZoomScale = InfiniteCanvasMetrics.minimumZoomScale
    canvasView.maximumZoomScale = InfiniteCanvasMetrics.maximumZoomScale
    canvasView.bouncesZoom = true
    canvasView.alwaysBounceHorizontal = true
    canvasView.alwaysBounceVertical = true
    canvasView.showsHorizontalScrollIndicator = false
    canvasView.showsVerticalScrollIndicator = false
    canvasView.contentInsetAdjustmentBehavior = .never
  }

  final class Coordinator: NSObject, PKCanvasViewDelegate {
    private let canvasController: InfiniteCanvasController
    private let toolPickerController: ToolPickerController
    private var onDrawingChanged: (PKDrawing) -> Void
    private var onDrawingChangeCommitted: (PKDrawing, PKCanvasView) -> Void
    private var isApplyingDrawing = false
    private(set) var appliedDrawingRevision = 0

    init(
      canvasController: InfiniteCanvasController,
      toolPickerController: ToolPickerController,
      onDrawingChanged: @escaping (PKDrawing) -> Void,
      onDrawingChangeCommitted: @escaping (PKDrawing, PKCanvasView) -> Void
    ) {
      self.canvasController = canvasController
      self.toolPickerController = toolPickerController
      self.onDrawingChanged = onDrawingChanged
      self.onDrawingChangeCommitted = onDrawingChangeCommitted
    }

    func update(
      onDrawingChanged: @escaping (PKDrawing) -> Void,
      onDrawingChangeCommitted: @escaping (PKDrawing, PKCanvasView) -> Void
    ) {
      self.onDrawingChanged = onDrawingChanged
      self.onDrawingChangeCommitted = onDrawingChangeCommitted
    }

    func apply(_ drawing: PKDrawing, revision: Int, to canvasView: PKCanvasView) {
      isApplyingDrawing = true
      canvasView.drawing = drawing
      appliedDrawingRevision = revision
      isApplyingDrawing = false
    }

    func register(_ canvasView: PKCanvasView) {
      canvasController.attach(canvasView)
      toolPickerController.register(canvasView)
    }

    func unregister(_ canvasView: PKCanvasView) {
      canvasController.persistCurrentViewport()
      canvasController.detach(canvasView)
      toolPickerController.unregister(canvasView)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      guard !isApplyingDrawing else { return }
      onDrawingChanged(canvasView.drawing)
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
      toolPickerController.focus(canvasView)
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
      DispatchQueue.main.asyncAfter(
        deadline: .now() + .milliseconds(30),
        execute: { [weak self, weak canvasView] in
          guard let self, let canvasView else { return }
          self.onDrawingChangeCommitted(canvasView.drawing, canvasView)
        })
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      guard let canvasView = scrollView as? PKCanvasView else { return }
      canvasController.syncViewport(from: canvasView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      guard let canvasView = scrollView as? PKCanvasView else { return }
      canvasController.syncViewport(from: canvasView)
    }

    func scrollViewDidEndZooming(
      _ scrollView: UIScrollView,
      with view: UIView?,
      atScale scale: CGFloat
    ) {
      canvasController.persistCurrentViewport()
    }

    func scrollViewDidEndDragging(
      _ scrollView: UIScrollView,
      willDecelerate decelerate: Bool
    ) {
      guard !decelerate else { return }
      canvasController.persistCurrentViewport()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      canvasController.persistCurrentViewport()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
      canvasController.persistCurrentViewport()
    }

  }
}

final class InfiniteCanvasHostView: UIView {
  let canvasView = PKCanvasView()
  var onAttachedToWindow: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    canvasView.frame = bounds
    canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(canvasView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else { return }
    onAttachedToWindow?()
  }
}
