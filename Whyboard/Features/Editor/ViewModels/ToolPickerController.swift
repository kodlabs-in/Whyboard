import Foundation
import Observation
import PencilKit

@Observable
final class ToolPickerController {
  let toolPicker: PKToolPicker
  private(set) var canUndo = false
  private(set) var canRedo = false

  @ObservationIgnored private let canvases = NSHashTable<PKCanvasView>.weakObjects()
  @ObservationIgnored private weak var activeCanvasView: PKCanvasView?

  init() {
    toolPicker = PKToolPicker()
    toolPicker.stateAutosaveName = "Whyboard.ToolPicker"
  }

  func register(_ canvasView: PKCanvasView) {
    canvases.add(canvasView)
    toolPicker.addObserver(canvasView)
    if activeCanvasView == nil {
      focus(canvasView)
    }
  }

  func focus(_ canvasView: PKCanvasView) {
    activeCanvasView = canvasView
    toolPicker.setVisible(true, forFirstResponder: canvasView)
    canvasView.becomeFirstResponder()
    refreshUndoState()
  }

  func unregister(_ canvasView: PKCanvasView) {
    canvases.remove(canvasView)
    toolPicker.removeObserver(canvasView)
    guard activeCanvasView === canvasView else { return }
    activeCanvasView = nil

    if let replacement = canvases.allObjects.first {
      focus(replacement)
    } else {
      refreshUndoState()
    }
  }

  func drawingDidChange(on canvasView: PKCanvasView) {
    guard activeCanvasView === canvasView else { return }
    refreshUndoState()
  }

  func undo() {
    activeCanvasView?.undoManager?.undo()
    refreshUndoState()
  }

  func redo() {
    activeCanvasView?.undoManager?.redo()
    refreshUndoState()
  }

  private func refreshUndoState() {
    canUndo = activeCanvasView?.undoManager?.canUndo == true
    canRedo = activeCanvasView?.undoManager?.canRedo == true
  }
}
