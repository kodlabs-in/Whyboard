import Foundation
import SwiftData

@Model
final class Page {
  @Attribute(.unique) var id: UUID
  var noteID: UUID
  var sortOrder: Int
  var contentRevision: Int64
  var drawingRelativePath: String
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    noteID: UUID,
    sortOrder: Int,
    contentRevision: Int64 = 0,
    drawingRelativePath: String? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.noteID = noteID
    self.sortOrder = sortOrder
    self.contentRevision = contentRevision
    self.drawingRelativePath = drawingRelativePath ?? "\(id.uuidString.lowercased()).drawing"
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
