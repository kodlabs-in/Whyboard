import Foundation
import SwiftData
import Testing

@testable import Whyboard

@MainActor
struct EditorControllerTests {
  @Test func insertReorderAndDeleteKeepStablePageIdentities() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let first = Page(noteID: note.id, sortOrder: 0)
    context.insert(note)
    context.insert(first)
    try context.save()
    let repository = DrawingRepository(directories: directories)
    let controller = EditorController(note: note, drawingRepository: repository)

    let secondID = controller.insertPage(
      relativeTo: first,
      after: true,
      pages: [first],
      context: context)
    var pages = try context.fetch(FetchDescriptor<Page>())
    let stableIDs = Set(pages.map(\.id))
    controller.movePages(from: [1], to: 0, pages: pages, context: context)
    pages = PageOrdering.ordered(try context.fetch(FetchDescriptor<Page>()))

    #expect(pages.map(\.id) == [secondID, first.id])
    #expect(Set(pages.map(\.id)) == stableIDs)
    #expect(pages.map(\.sortOrder) == [0, 1])

    guard let second = pages.first(where: { $0.id == secondID }) else {
      Issue.record("Inserted page was not found")
      return
    }
    controller.deletePage(second, pages: pages, context: context)
    try await Task.sleep(for: .milliseconds(50))
    pages = try context.fetch(FetchDescriptor<Page>())

    #expect(pages.map(\.id) == [first.id])
    #expect(pages.first?.sortOrder == 0)
  }

  @Test func deletingTheOnlyPageIsRejected() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    context.insert(note)
    context.insert(page)
    let controller = EditorController(
      note: note,
      drawingRepository: DrawingRepository(directories: directories))

    controller.deletePage(page, pages: [page], context: context)

    #expect(controller.errorMessage == "A note must always contain at least one page.")
    #expect(try context.fetchCount(FetchDescriptor<Page>()) == 1)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}
