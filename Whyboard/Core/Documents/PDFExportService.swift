import CoreGraphics
import Foundation
import PencilKit

enum PDFExportError: LocalizedError {
  case sourceSaveFailed
  case createFailed
  case cancelled

  var errorDescription: String? {
    switch self {
    case .sourceSaveFailed:
      "Save the note before exporting it."
    case .createFailed:
      "Whyboard couldn't create the PDF export."
    case .cancelled:
      "PDF export was cancelled."
    }
  }
}

struct PDFExportResult: Identifiable, Sendable {
  let id = UUID()
  let url: URL
  let pageCount: Int
}

private nonisolated struct PDFExportPageInput: Sendable {
  let noteID: UUID
  let pageID: UUID
  let elements: [WorkspaceElement]
  let layout: PagePreviewLayout
  let background: ImportedPDFBackground?
}

private nonisolated struct PDFPageRenderContext {
  let paperStyle: NotePaperStyle
  let renderer: PagePreviewRenderer
  let context: CGContext
  let mediaBox: CGRect
}

private actor PDFExportWorker {
  let drawingRepository: DrawingRepository

  init(drawingRepository: DrawingRepository) {
    self.drawingRepository = drawingRepository
  }

  func writePDF(
    pages: [PDFExportPageInput],
    paperStyle: NotePaperStyle,
    outputURL: URL,
    progress: AsyncStream<Double>.Continuation
  ) async throws -> Int {
    try Task.checkCancellation()
    var mediaBox = CGRect(origin: .zero, size: CanonicalPage.size)
    guard
      let consumer = CGDataConsumer(url: outputURL as CFURL),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { throw PDFExportError.createFailed }
    let renderContext = PDFPageRenderContext(
      paperStyle: paperStyle,
      renderer: PagePreviewRenderer(
        attachments: drawingRepository.attachments,
        documents: drawingRepository.documents),
      context: context,
      mediaBox: mediaBox)

    for (index, page) in pages.enumerated() {
      try Task.checkCancellation()
      try await renderPage(page, renderContext: renderContext)
      progress.yield(Double(index + 1) / Double(max(pages.count, 1)))
    }
    try Task.checkCancellation()
    context.closePDF()
    return pages.count
  }

  private func renderPage(
    _ page: PDFExportPageInput,
    renderContext: PDFPageRenderContext
  ) async throws {
    let interval = AppSignpost.interval("PDF Page Render")
    defer { interval.end() }
    let drawing = try await drawingRepository.load(
      pageID: page.pageID,
      noteID: page.noteID)
    autoreleasepool {
      let snapshot = PagePreviewSnapshot(
        drawing: drawing,
        elements: page.elements,
        layout: page.layout,
        paperStyle: renderContext.paperStyle,
        background: page.background)
      let context = renderContext.context
      context.beginPDFPage(nil)
      context.saveGState()
      context.translateBy(x: 0, y: renderContext.mediaBox.height)
      context.scaleBy(x: 1, y: -1)
      renderContext.renderer.drawForExport(
        snapshot,
        noteID: page.noteID,
        pageID: page.pageID,
        in: context,
        outputSize: renderContext.mediaBox.size)
      context.restoreGState()
      context.endPDFPage()
    }
  }
}

@MainActor
struct PDFExportService {
  let drawingRepository: DrawingRepository

  func export(
    note: Note,
    pages: [Page],
    defaultPaperStyle: NotePaperStyle,
    onProgress: @escaping (Double) -> Void = { _ in }
  ) async throws -> PDFExportResult {
    guard await drawingRepository.pendingSaves.flush(noteID: note.id) else {
      throw PDFExportError.sourceSaveFailed
    }
    let orderedPages = PageOrdering.ordered(pages.filter { $0.noteID == note.id })
    let outputURL = exportURL(for: note)
    let inputs = orderedPages.map { page in
      PDFExportPageInput(
        noteID: note.id,
        pageID: page.id,
        elements: WorkspaceElementCoding.decode(page.workspaceElementsData),
        layout: PagePreviewLayout(note: note),
        background: ImportedPDFBackground(page: page))
    }
    let (progress, continuation) = AsyncStream<Double>.makeStream()
    let progressTask = Task {
      for await value in progress {
        onProgress(value)
      }
    }
    defer {
      continuation.finish()
      progressTask.cancel()
    }

    do {
      let count = try await PDFExportWorker(drawingRepository: drawingRepository).writePDF(
        pages: inputs,
        paperStyle: note.paperStyle.resolved(defaultRawValue: defaultPaperStyle.rawValue),
        outputURL: outputURL,
        progress: continuation)
      return PDFExportResult(url: outputURL, pageCount: count)
    } catch is CancellationError {
      try? FileManager.default.removeItem(at: outputURL)
      throw PDFExportError.cancelled
    } catch {
      try? FileManager.default.removeItem(at: outputURL)
      throw error
    }
  }

  private func exportURL(for note: Note) -> URL {
    let invalid = CharacterSet.alphanumerics.union(.whitespaces).inverted
    let sanitized = note.title.components(separatedBy: invalid).joined()
      .trimmingCharacters(in: .whitespaces)
    let base = sanitized.isEmpty ? "Whyboard Note" : sanitized
    let timestamp = ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    return drawingRepository.exportsDirectory
      .appending(path: "\(base) \(timestamp).pdf")
  }
}
