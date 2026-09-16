import PencilKit
import SwiftData
import Testing
import UIKit

@testable import Whyboard

@MainActor
struct ScaleArchitectureTests {
  @Test func populatedNotebooksPersistAndPreviewEveryPage() async throws {
    try await verifyPersistedNotebook(pageCount: 100)
    try await verifyPersistedNotebook(pageCount: 200)
    try await verifyPersistedNotebook(pageCount: 500)
  }

  @Test func thousandNoteLibrarySortAndRecentSurfacesAreDeterministic() {
    let (_, notes) = StressFixtureFactory.library(noteCount: 1_000)
    let sorted = NoteSorting.sorted(notes, by: .updatedDate, direction: .descending)
    let recent = NoteSorting.recentlyOpened(notes)
    let recentDates = recent.compactMap(\.lastOpenedAt)

    #expect(sorted.count == 1_000)
    #expect(recent.count == 8)
    #expect(recentDates == recentDates.sorted(by: >))
  }

  private func verifyPersistedNotebook(pageCount: Int) async throws {
    let fixture = try await StressFixtureFactory.notebook(pageCount: pageCount)
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }

    #expect(fixture.pages.count == pageCount)
    #expect(try fixture.context.fetchCount(FetchDescriptor<Page>()) == pageCount)
    let orderedPageIDs = fixture.pages.map(\.id)
    for page in fixture.pages {
      try await verify(page: page, orderedPageIDs: orderedPageIDs, in: fixture)
    }
  }

  private func verify(
    page: Page,
    orderedPageIDs: [UUID],
    in fixture: PopulatedNotebookFixture
  ) async throws {
    let drawing = try await fixture.repository.load(pageID: page.id, noteID: fixture.note.id)
    let elements = WorkspaceElementCoding.decode(page.workspaceElementsData)
    let image = try #require(elements.first(where: { $0.kind == .image }))
    let filename = try #require(image.assetFilename)
    let imageURL = fixture.repository.attachments.fileURL(
      noteID: fixture.note.id,
      pageID: page.id,
      filename: filename)
    let preview = await fixture.repository.preview(
      for: PagePreviewDescriptor(
        page: page,
        noteKind: .infinitePages,
        paperStyle: .white))
    let livePageIDs = PageWindow.livePageIDs(
      orderedPageIDs: orderedPageIDs,
      visiblePageIDs: [page.id])

    #expect(drawing.strokes.count == 6)
    #expect(elements.count == 6)
    #expect(UIImage(contentsOfFile: imageURL.path) != nil)
    #expect(preview?.size.width ?? 0 > 0)
    #expect(livePageIDs.count <= 4)
  }
}
