import Foundation
import SwiftData

enum LibrarySeeder {
  static func seedIfNeeded(in context: ModelContext) throws {
    var descriptor = FetchDescriptor<Folder>(
      predicate: #Predicate { $0.isSystem })
    descriptor.fetchLimit = 1

    guard try context.fetch(descriptor).isEmpty else { return }
    context.insert(Folder(name: "Unfiled Notes", isSystem: true))
    try context.save()
  }
}
