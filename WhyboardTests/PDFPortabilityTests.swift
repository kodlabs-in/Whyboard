import PDFKit
import SwiftData
import Testing
import UIKit

@testable import Whyboard

@MainActor
struct PDFPortabilityTests {
  @Test func importPublishesOneStablePagePerPDFPageAndKeepsSourceUnchanged() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let source = directories.root.appending(path: "Lecture.pdf")
    try makePDF(at: source, pageCount: 3)
    let originalData = try Data(contentsOf: source)
    let folder = Folder(name: "Classes")
    context.insert(folder)

    let noteID = try await PDFImportService(drawingRepository: repository)
      .importPDF(
        at: source,
        folderID: folder.id,
        existingNotes: [],
        context: context)

    let note = try #require(
      try context.fetch(FetchDescriptor<Note>()).first { $0.id == noteID })
    let document = try #require(
      try context.fetch(FetchDescriptor<ImportedDocument>()).first { $0.noteID == noteID })
    let pages = PageOrdering.ordered(
      try context.fetch(FetchDescriptor<Page>()).filter { $0.noteID == noteID })

    #expect(note.title == "Lecture")
    #expect(note.kind == .infinitePages)
    #expect(document.pageCount == 3)
    #expect(pages.map(\.sortOrder) == [0, 1, 2])
    #expect(pages.map(\.importedDocumentID) == [document.id, document.id, document.id])
    #expect(pages.map(\.importedDocumentPageIndex) == [0, 1, 2])
    #expect(try Data(contentsOf: source) == originalData)
    #expect(
      FileManager.default.fileExists(
        atPath: repository.documents.fileURL(
          noteID: noteID,
          documentID: document.id
        ).path))
  }

  @Test func invalidPDFNeverPublishesMetadata() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let source = directories.root.appending(path: "Broken.pdf")
    try Data("not a pdf".utf8).write(to: source)

    await #expect(throws: DocumentStorageError.self) {
      try await PDFImportService(drawingRepository: repository)
        .importPDF(
          at: source,
          folderID: UUID(),
          existingNotes: [],
          context: context)
    }

    #expect(try context.fetchCount(FetchDescriptor<Note>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<Page>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<ImportedDocument>()) == 0)
  }

  @Test func exportStreamsPagesInNotebookOrderAndReopensSuccessfully() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let note = Note(folderID: UUID(), title: "Ordered Export")
    let pages = [
      Page(noteID: note.id, sortOrder: 2),
      Page(noteID: note.id, sortOrder: 0),
      Page(noteID: note.id, sortOrder: 1),
    ]

    let result = try await PDFExportService(drawingRepository: repository)
      .export(note: note, pages: pages, defaultPaperStyle: .white)
    let reopened = try #require(PDFDocument(url: result.url))

    #expect(result.pageCount == 3)
    #expect(reopened.pageCount == 3)
    #expect(FileManager.default.fileExists(atPath: result.url.path))
  }

  @Test func fiveHundredPageImportCreatesReferencesWithoutEagerPreviews() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let source = directories.root.appending(path: "Reference-500.pdf")
    try makePDF(at: source, pageCount: 500)

    let noteID = try await PDFImportService(drawingRepository: repository)
      .importPDF(
        at: source,
        folderID: UUID(),
        existingNotes: [],
        context: context)
    let pages = try context.fetch(FetchDescriptor<Page>()).filter { $0.noteID == noteID }
    let previewFiles = try FileManager.default.contentsOfDirectory(
      at: directories.previews,
      includingPropertiesForKeys: nil)

    #expect(pages.count == 500)
    #expect(Set(pages.compactMap(\.importedDocumentID)).count == 1)
    #expect(previewFiles.isEmpty)
  }

  @Test func cancelledImportPublishesNoNoteOrPayload() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let source = directories.root.appending(path: "Cancelled.pdf")
    try makePDF(at: source, pageCount: 100)

    let task = Task {
      try await PDFImportService(drawingRepository: repository)
        .importPDF(
          at: source,
          folderID: UUID(),
          existingNotes: [],
          context: context)
    }
    task.cancel()
    await #expect(throws: PDFImportError.self) { try await task.value }

    #expect(try context.fetchCount(FetchDescriptor<Note>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<Page>()) == 0)
    let payloads = try FileManager.default.contentsOfDirectory(
      at: directories.documents,
      includingPropertiesForKeys: nil)
    #expect(payloads.isEmpty)
  }

  @Test func cancelledExportRemovesTemporaryOutput() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let note = Note(folderID: UUID(), title: "Cancelled Export")
    let pages = (0..<500).map { Page(noteID: note.id, sortOrder: $0) }

    let task = Task {
      try await PDFExportService(drawingRepository: repository)
        .export(note: note, pages: pages, defaultPaperStyle: .white)
    }
    task.cancel()
    await #expect(throws: PDFExportError.self) { try await task.value }

    let outputs = try FileManager.default.contentsOfDirectory(
      at: directories.exports,
      includingPropertiesForKeys: nil)
    #expect(outputs.isEmpty)
  }

  private func makePDF(at url: URL, pageCount: Int) throws {
    let renderer = UIGraphicsPDFRenderer(
      bounds: CGRect(x: 0, y: 0, width: 240, height: 320))
    try renderer.writePDF(to: url) { context in
      for index in 0..<pageCount {
        context.beginPage()
        NSString(string: "Whyboard fixture page \(index + 1)").draw(
          at: CGPoint(x: 24, y: 24),
          withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
      }
    }
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self, ImportedDocument.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}
