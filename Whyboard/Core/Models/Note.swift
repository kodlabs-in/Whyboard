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

  init(
    id: UUID = UUID(),
    folderID: UUID,
    title: String = "Untitled Note",
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastOpenedAt: Date? = nil,
    lastScrollOffset: Double = 0
  ) {
    self.id = id
    self.folderID = folderID
    self.title = title
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastOpenedAt = lastOpenedAt
    self.lastScrollOffset = lastScrollOffset
  }
}
