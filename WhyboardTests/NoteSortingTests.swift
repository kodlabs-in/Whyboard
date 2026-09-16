import Foundation
import Testing

@testable import Whyboard

@MainActor
struct NoteSortingTests {
  @Test func sortsEveryFieldInBothDirections() throws {
    let early = Date(timeIntervalSince1970: 100)
    let late = Date(timeIntervalSince1970: 200)
    let alphaID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let betaID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let alpha = Note(
      id: alphaID,
      folderID: UUID(),
      title: "Alpha",
      createdAt: late,
      updatedAt: early)
    let beta = Note(
      id: betaID,
      folderID: UUID(),
      title: "Beta",
      createdAt: early,
      updatedAt: late)

    #expect(
      NoteSorting.sorted([beta, alpha], by: .name, direction: .ascending).map(\.id)
        == [alpha.id, beta.id])
    #expect(
      NoteSorting.sorted([alpha, beta], by: .name, direction: .descending).map(\.id)
        == [beta.id, alpha.id])
    #expect(
      NoteSorting.sorted([alpha, beta], by: .createdDate, direction: .ascending).map(\.id)
        == [beta.id, alpha.id])
    #expect(
      NoteSorting.sorted([alpha, beta], by: .updatedDate, direction: .descending).map(\.id)
        == [beta.id, alpha.id])
  }

  @Test func equalValuesUseStableIdentifiers() throws {
    let date = Date(timeIntervalSince1970: 100)
    let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let first = Note(
      id: firstID,
      folderID: UUID(),
      title: "Same",
      createdAt: date,
      updatedAt: date)
    let second = Note(
      id: secondID,
      folderID: UUID(),
      title: "Same",
      createdAt: date,
      updatedAt: date)

    #expect(
      NoteSorting.sorted([second, first], by: .updatedDate, direction: .descending).map(\.id)
        == [first.id, second.id])
  }

  @Test func recentsUseOpenTimeAndExcludeUnopenedNotes() {
    let folderID = UUID()
    let newest = Note(folderID: folderID, title: "Newest")
    newest.lastOpenedAt = Date(timeIntervalSince1970: 300)
    let older = Note(folderID: folderID, title: "Older")
    older.lastOpenedAt = Date(timeIntervalSince1970: 100)
    let unopened = Note(folderID: folderID, title: "Unopened")

    #expect(
      NoteSorting.recentlyOpened([older, unopened, newest], limit: 1).map(\.id) == [newest.id])
    #expect(
      NoteSorting.recentlyOpened([older, unopened, newest]).map(\.id) == [newest.id, older.id])
    #expect(unopened.isFavorite == nil)
  }
}
