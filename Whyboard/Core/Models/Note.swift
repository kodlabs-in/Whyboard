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
  var noteKindRawValue: String?
  var canvasOffsetX: Double?
  var canvasOffsetY: Double?
  var canvasZoomScale: Double?
  var isFavorite: Bool?

  init(
    id: UUID = UUID(),
    folderID: UUID,
    title: String = "Untitled Note",
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastOpenedAt: Date? = nil,
    lastScrollOffset: Double = 0,
    paperStyle: NotePaperStyle = .defaultStyle,
    kind: NoteKind = .infinitePages,
    isFavorite: Bool? = nil
  ) {
    self.id = id
    self.folderID = folderID
    self.title = title
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastOpenedAt = lastOpenedAt
    self.lastScrollOffset = lastScrollOffset
    self.paperStyleRawValue = paperStyle == .automatic ? nil : paperStyle.rawValue
    self.noteKindRawValue = kind == .infinitePages ? nil : kind.rawValue
    self.isFavorite = isFavorite
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

  var kind: NoteKind {
    get {
      guard let noteKindRawValue else { return .infinitePages }
      return NoteKind(rawValue: noteKindRawValue) ?? .infinitePages
    }
    set {
      noteKindRawValue = newValue == .infinitePages ? nil : newValue.rawValue
    }
  }
}
