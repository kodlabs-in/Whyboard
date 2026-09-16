import Foundation

enum WorkspaceInteractionMode {
  case draw
  case arrange

  var actionName: String {
    switch self {
    case .draw: "Arrange Objects"
    case .arrange: "Return to Drawing"
    }
  }

  var systemImage: String {
    switch self {
    case .draw: "cursorarrow.motionlines"
    case .arrange: "pencil.tip"
    }
  }

  mutating func toggle() {
    self = self == .draw ? .arrange : .draw
  }
}
