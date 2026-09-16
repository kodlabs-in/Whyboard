import Foundation

enum PageNavigation {
  static func page(number: Int, in orderedPages: [Page]) -> Page? {
    guard orderedPages.indices.contains(number - 1) else { return nil }
    return orderedPages[number - 1]
  }

  static func number(of pageID: UUID?, in orderedPages: [Page]) -> Int {
    guard let pageID, let index = orderedPages.firstIndex(where: { $0.id == pageID }) else {
      return 1
    }
    return index + 1
  }
}
