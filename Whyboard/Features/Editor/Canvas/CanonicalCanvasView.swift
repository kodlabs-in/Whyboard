import PencilKit
import SwiftUI
import UIKit

struct CanonicalCanvasView: UIViewRepresentable {
  let drawing: PKDrawing
  let drawsWithFinger: Bool
  let toolPickerController: ToolPickerController
  let onDrawingChanged: (PKDrawing) -> Void
  let onFocused: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      toolPickerController: toolPickerController,
      onDrawingChanged: onDrawingChanged,
      onFocused: onFocused)
  }

  func makeUIView(context: Context) -> CanonicalCanvasHostView {
    let hostView = CanonicalCanvasHostView()
    let canvasView = hostView.canvasView
    context.coordinator.apply(drawing, to: canvasView)
    canvasView.delegate = context.coordinator
    canvasView.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly
    hostView.onAttachedToWindow = { [weak canvasView, weak coordinator = context.coordinator] in
      guard let canvasView, let coordinator else { return }
      coordinator.register(canvasView)
    }
    return hostView
  }

  func updateUIView(_ hostView: CanonicalCanvasHostView, context: Context) {
    context.coordinator.updateCallbacks(
      onDrawingChanged: onDrawingChanged,
      onFocused: onFocused)
    hostView.canvasView.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly

    if hostView.canvasView.drawing != drawing {
      context.coordinator.apply(drawing, to: hostView.canvasView)
    }
  }

  static func dismantleUIView(_ hostView: CanonicalCanvasHostView, coordinator: Coordinator) {
    coordinator.unregister(hostView.canvasView)
    hostView.canvasView.delegate = nil
  }

  final class Coordinator: NSObject, PKCanvasViewDelegate {
    private let toolPickerController: ToolPickerController
    private var onDrawingChanged: (PKDrawing) -> Void
    private var onFocused: () -> Void
    private var isApplyingDrawing = false

    init(
      toolPickerController: ToolPickerController,
      onDrawingChanged: @escaping (PKDrawing) -> Void,
      onFocused: @escaping () -> Void
    ) {
      self.toolPickerController = toolPickerController
      self.onDrawingChanged = onDrawingChanged
      self.onFocused = onFocused
    }

    func updateCallbacks(
      onDrawingChanged: @escaping (PKDrawing) -> Void,
      onFocused: @escaping () -> Void
    ) {
      self.onDrawingChanged = onDrawingChanged
      self.onFocused = onFocused
    }

    func apply(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
      isApplyingDrawing = true
      canvasView.drawing = drawing
      isApplyingDrawing = false
    }

    func register(_ canvasView: PKCanvasView) {
      toolPickerController.register(canvasView)
    }

    func unregister(_ canvasView: PKCanvasView) {
      toolPickerController.unregister(canvasView)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      guard !isApplyingDrawing else { return }
      onDrawingChanged(canvasView.drawing)
      toolPickerController.drawingDidChange(on: canvasView)
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
      onFocused()
      toolPickerController.focus(canvasView)
    }
  }
}

final class CanonicalCanvasHostView: UIView {
  let canvasView = PKCanvasView()
  var onAttachedToWindow: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    configureCanvas()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      onAttachedToWindow?()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let scale = bounds.width / CanonicalPage.size.width
    canvasView.transform = .identity
    canvasView.bounds = CGRect(origin: .zero, size: CanonicalPage.size)
    canvasView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    canvasView.transform = CGAffineTransform(scaleX: scale, y: scale)
  }

  private func configureCanvas() {
    clipsToBounds = true
    backgroundColor = .clear
    canvasView.backgroundColor = .clear
    canvasView.isOpaque = false
    canvasView.isScrollEnabled = false
    canvasView.alwaysBounceHorizontal = false
    canvasView.alwaysBounceVertical = false
    canvasView.contentSize = CanonicalPage.size
    addSubview(canvasView)
  }
}
