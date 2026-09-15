import Foundation

enum PageOrdering {
  static func ordered(_ pages: [Page]) -> [Page] {
    pages.sorted {
      if $0.sortOrder == $1.sortOrder {
        return $0.createdAt < $1.createdAt
      }
      return $0.sortOrder < $1.sortOrder
    }
  }

  static func renumber(_ pages: [Page]) {
    for (index, page) in pages.enumerated() {
      page.sortOrder = index
      page.updatedAt = Date()
    }
  }
}
