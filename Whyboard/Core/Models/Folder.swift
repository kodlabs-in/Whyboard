import Foundation
import SwiftData

@Model
final class Folder {
  @Attribute(.unique) var id: UUID
  var parentFolderID: UUID?
  var name: String
  var sortOrder: Int
  var createdAt: Date
  var updatedAt: Date
  var isSystem: Bool

  init(
    id: UUID = UUID(),
    parentFolderID: UUID? = nil,
    name: String,
    sortOrder: Int = 0,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    isSystem: Bool = false
  ) {
    self.id = id
    self.parentFolderID = parentFolderID
    self.name = name
    self.sortOrder = sortOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isSystem = isSystem
  }
}
