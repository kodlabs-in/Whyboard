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

  @Test func largeLibraryPageSummaryCountsPagesAndChoosesTheFirstCoverInOneIndex() {
    let noteIDs = (0..<1_000).map { _ in UUID() }
    let pages = (0..<20_000).map { index in
      Page(noteID: noteIDs[index % noteIDs.count], sortOrder: 19_999 - index)
    }

    let summary = LibraryPageSummary(pages: pages)

    #expect(summary.pageCounts.count == 1_000)
    #expect(summary.pageCounts.values.allSatisfy { $0 == 20 })
    for (noteID, cover) in summary.coverPages {
      let expectedOrder = pages.lazy
        .filter { $0.noteID == noteID }
        .map(\.sortOrder)
        .min()
      #expect(cover.sortOrder == expectedOrder)
    }
  }

  @Test func swiftDataPageSummaryStoreAggregatesAcrossProjectedBatches() async throws {
    let schema = Schema([Page.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = container.mainContext
    let noteIDs = [UUID(), UUID()]
    let expectedCover = Page(noteID: noteIDs[1], sortOrder: 0, contentRevision: 7)
    expectedCover.workspaceElementsData = Data("[]".utf8)
    context.insert(expectedCover)
    for index in 1..<10 {
      context.insert(Page(noteID: noteIDs[(index + 1) % noteIDs.count], sortOrder: index))
    }
    try context.save()

    let summary = try await LibraryPageSummaryStore(modelContainer: container)
      .load(batchSize: 4)

    #expect(summary.pageCounts[noteIDs[0]] == 5)
    #expect(summary.pageCounts[noteIDs[1]] == 5)
    #expect(summary.coverPages[noteIDs[0]]?.sortOrder == 1)
    #expect(summary.coverPages[noteIDs[1]]?.pageID == expectedCover.id)
    #expect(summary.coverPages[noteIDs[1]]?.contentRevision == 7)
    #expect(summary.coverPages[noteIDs[1]]?.workspaceElementsData == Data("[]".utf8))
  }

  @Test func pageSummaryRequestTracksNoteRevisionButNotLastOpenedAt() {
    let note = Note(
      folderID: UUID(),
      updatedAt: Date(timeIntervalSince1970: 100))
    let initial = LibraryPageSummaryRequest(notes: [note])

    note.lastOpenedAt = Date(timeIntervalSince1970: 200)
    #expect(LibraryPageSummaryRequest(notes: [note]) == initial)

    note.updatedAt = Date(timeIntervalSince1970: 300)
    #expect(LibraryPageSummaryRequest(notes: [note]) != initial)
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
