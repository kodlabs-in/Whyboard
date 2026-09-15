import Foundation
import Testing

@testable import Whyboard

@MainActor
struct PageOrderingTests {
  @Test func ordersByPositionThenCreationDate() {
    let noteID = UUID()
    let later = Page(
      noteID: noteID,
      sortOrder: 0,
      createdAt: Date(timeIntervalSince1970: 20))
    let earlier = Page(
      noteID: noteID,
      sortOrder: 0,
      createdAt: Date(timeIntervalSince1970: 10))
    let final = Page(noteID: noteID, sortOrder: 2)

    #expect(
      PageOrdering.ordered([final, later, earlier]).map(\.id) == [earlier.id, later.id, final.id])
  }

  @Test func renumberPreservesPageIdentity() {
    let noteID = UUID()
    let pages = [
      Page(noteID: noteID, sortOrder: 9),
      Page(noteID: noteID, sortOrder: 4),
      Page(noteID: noteID, sortOrder: 18),
    ]
    let identities = pages.map(\.id)

    PageOrdering.renumber(pages)

    #expect(pages.map(\.sortOrder) == [0, 1, 2])
    #expect(pages.map(\.id) == identities)
  }
}
