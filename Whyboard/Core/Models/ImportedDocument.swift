import Foundation
import SwiftData

@Model
final class ImportedDocument {
  static let currentFormatVersion = 1

  @Attribute(.unique) var id: UUID
  var noteID: UUID
  var filename: String
  var pageCount: Int
  var createdAt: Date
  var formatVersion: Int

  init(
    id: UUID = UUID(),
    noteID: UUID,
    filename: String? = nil,
    pageCount: Int,
    createdAt: Date = Date(),
    formatVersion: Int = ImportedDocument.currentFormatVersion
  ) {
    self.id = id
    self.noteID = noteID
    self.filename = filename ?? "\(id.uuidString.lowercased()).pdf"
    self.pageCount = pageCount
    self.createdAt = createdAt
    self.formatVersion = formatVersion
  }
}
