import Foundation
import Observation
import PencilKit

@Observable
final class ToolPickerController {
  let toolPicker: PKToolPicker
  @ObservationIgnored private let canvases = NSHashTable<PKCanvasView>.weakObjects()
  @ObservationIgnored private weak var activeCanvasView: PKCanvasView?

  init() {
    toolPicker = PKToolPicker()
    if ProcessInfo.processInfo.environment["WHYBOARD_UI_TEST_DRAW_WITH_FINGER"] == "1" {
      if let inkItem = toolPicker.toolItems.first(where: { $0 is PKToolPickerInkingItem }) {
        toolPicker.selectedToolItem = inkItem
      }
    } else {
      toolPicker.stateAutosaveName = "Whyboard.ToolPicker"
    }
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
  }

  func unregister(_ canvasView: PKCanvasView) {
    canvases.remove(canvasView)
    toolPicker.removeObserver(canvasView)
    guard activeCanvasView === canvasView else { return }
    activeCanvasView = nil

    if let replacement = canvases.allObjects.first {
      focus(replacement)
    }
  }
}
