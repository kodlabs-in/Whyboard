import Foundation

enum NoteSortField: String, CaseIterable, Identifiable {
  case name
  case createdDate
  case updatedDate

  static let storageKey = "libraryNoteSortField"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .name: "Name"
    case .createdDate: "Created Date"
    case .updatedDate: "Updated Date"
    }
  }
}

enum NoteSortDirection: String, CaseIterable, Identifiable {
  case ascending
  case descending

  static let storageKey = "libraryNoteSortDirection"

  var id: String { rawValue }
  var title: String { rawValue.capitalized }

  func ordersBefore(_ comparison: ComparisonResult) -> Bool {
    switch self {
    case .ascending: comparison == .orderedAscending
    case .descending: comparison == .orderedDescending
    }
  }
}

enum NoteSorting {
  static func sorted(
    _ notes: [Note],
    by field: NoteSortField,
    direction: NoteSortDirection
  ) -> [Note] {
    notes.sorted { left, right in
      precedes(left, right, field: field, direction: direction)
    }
  }

  static func recentlyOpened(_ notes: [Note], limit: Int = 8) -> [Note] {
    let ordered = notes.compactMap { note -> (Note, Date)? in
      guard let openedAt = note.lastOpenedAt else { return nil }
      return (note, openedAt)
    }.sorted { left, right in
      guard left.1 == right.1 else { return left.1 > right.1 }
      return left.0.id.uuidString < right.0.id.uuidString
    }
    return Array(ordered.prefix(max(0, limit)).map(\.0))
  }

  private static func precedes(
    _ left: Note,
    _ right: Note,
    field: NoteSortField,
    direction: NoteSortDirection
  ) -> Bool {
    let result = comparison(left, right, field: field)
    guard result == .orderedSame else { return direction.ordersBefore(result) }
    return left.id.uuidString < right.id.uuidString
  }

  private static func comparison(
    _ left: Note,
    _ right: Note,
    field: NoteSortField
  ) -> ComparisonResult {
    switch field {
    case .name:
      left.title.localizedStandardCompare(right.title)
    case .createdDate:
      left.createdAt.compare(right.createdAt)
    case .updatedDate:
      left.updatedAt.compare(right.updatedAt)
    }
  }
}
