import SwiftUI
import UIKit

extension LibraryView {
  func presentPDFImport(in location: LibraryLocation) {
    guard documentTask == nil else { return }
    pdfImportLocation = location
    isPickingPDF = true
  }

  func handlePDFSelection(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let source = urls.first else { return }
      startPDFImport(source)
    case .failure(let error):
      controller.errorMessage = error.localizedDescription
    }
  }

  func startPDFImport(_ source: URL) {
    guard documentTask == nil else { return }
    guard
      let folderID = controller.storageFolderID(
        for: pdfImportLocation,
        folders: folders)
    else {
      controller.errorMessage = "Whyboard couldn't find the current folder."
      return
    }
    documentOperation = DocumentOperationPresentation(title: "Importing PDF")
    documentTask = Task {
      do {
        let noteID = try await PDFImportService(drawingRepository: drawingRepository)
          .importPDF(
            at: source,
            folderID: folderID,
            paperStyle: defaultPaperStyle,
            existingNotes: notes,
            context: modelContext,
            onProgress: updateDocumentProgress)
        finishDocumentOperation(announcement: "PDF import complete")
        routes.append(.note(noteID))
      } catch PDFImportError.cancelled {
        finishDocumentOperation(announcement: "PDF import cancelled")
      } catch {
        finishDocumentOperation(error: error)
      }
    }
  }

  func exportNote(_ note: Note) {
    guard documentTask == nil else { return }
    documentOperation = DocumentOperationPresentation(title: "Exporting PDF")
    let defaultStyle =
      NotePaperStyle(
        rawValue: AppPreferences.store.string(forKey: NotePaperStyle.defaultStorageKey) ?? ""
      ) ?? .white
    documentTask = Task {
      do {
        let result = try await PDFExportService(drawingRepository: drawingRepository)
          .export(
            note: note,
            pages: pages,
            defaultPaperStyle: defaultStyle,
            onProgress: updateDocumentProgress)
        finishDocumentOperation(announcement: "PDF export complete")
        exportedPDF = result
      } catch PDFExportError.cancelled {
        finishDocumentOperation(announcement: "PDF export cancelled")
      } catch {
        finishDocumentOperation(error: error)
      }
    }
  }

  func updateDocumentProgress(_ progress: Double) {
    guard var operation = documentOperation else { return }
    operation.progress = min(max(progress, 0), 1)
    documentOperation = operation
  }

  func cancelDocumentOperation() {
    documentTask?.cancel()
  }

  func finishDocumentOperation(announcement: String) {
    documentTask = nil
    documentOperation = nil
    UIAccessibility.post(notification: .announcement, argument: announcement)
  }

  func finishDocumentOperation(error: Error) {
    documentTask = nil
    documentOperation = nil
    controller.errorMessage = error.localizedDescription
  }

  func removeExportedPDF() {
    guard let url = exportedPDF?.url else { return }
    try? FileManager.default.removeItem(at: url)
  }
}
