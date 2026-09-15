import Foundation
import SwiftData

@Model
final class Note {
  @Attribute(.unique) var id: UUID
  var folderID: UUID
  var title: String
  var createdAt: Date
  var updatedAt: Date
  var lastOpenedAt: Date?
  var lastScrollOffset: Double
  var paperStyleRawValue: String?

  init(
    id: UUID = UUID(),
    folderID: UUID,
    title: String = "Untitled Note",
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastOpenedAt: Date? = nil,
    lastScrollOffset: Double = 0,
    paperStyle: NotePaperStyle = .automatic
  ) {
    self.id = id
    self.folderID = folderID
    self.title = title
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastOpenedAt = lastOpenedAt
    self.lastScrollOffset = lastScrollOffset
    self.paperStyleRawValue = paperStyle == .automatic ? nil : paperStyle.rawValue
  }

  var paperStyle: NotePaperStyle {
    get {
      guard let paperStyleRawValue else { return .automatic }
      return NotePaperStyle(rawValue: paperStyleRawValue) ?? .automatic
    }
    set {
      paperStyleRawValue = newValue == .automatic ? nil : newValue.rawValue
    }
  }
}
