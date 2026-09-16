import Foundation

enum NoteKind: String, CaseIterable, Identifiable, Sendable {
  case infinitePages
  case infiniteCanvas

  var id: String { rawValue }

  var name: String {
    switch self {
    case .infinitePages: "Infinite Pages"
    case .infiniteCanvas: "Infinite Canvas"
    }
  }

  var description: String {
    switch self {
    case .infinitePages:
      "A continuous stack of paper pages that grows with your ideas."
    case .infiniteCanvas:
      "A freeform space for sketching, panning, and zooming."
    }
  }

  var systemImage: String {
    switch self {
    case .infinitePages: "doc.on.doc"
    case .infiniteCanvas: "rectangle.dashed"
    }
  }

  func libraryDetail(pageCount: Int) -> String {
    switch self {
    case .infinitePages:
      pageCount == 1 ? "1 page" : "\(pageCount) pages"
    case .infiniteCanvas:
      "Infinite canvas"
    }
  }
}
