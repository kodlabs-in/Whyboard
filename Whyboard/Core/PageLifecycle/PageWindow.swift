import Foundation

enum PageWindow {
  static func livePageIDs(
    orderedPageIDs: [UUID],
    visiblePageIDs: Set<UUID>,
    leading: Int = 1,
    trailing: Int = 2
  ) -> Set<UUID> {
    let indices = visiblePageIDs.compactMap { orderedPageIDs.firstIndex(of: $0) }
    guard let firstVisible = indices.min(), let lastVisible = indices.max() else { return [] }

    let lowerBound = max(0, firstVisible - leading)
    let upperBound = min(orderedPageIDs.count - 1, lastVisible + trailing)
    return Set(orderedPageIDs[lowerBound...upperBound])
  }
}
