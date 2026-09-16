import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class NoteExportController {
  var operation: DocumentOperationPresentation?
  var result: PDFExportResult?
  var errorMessage: String?

  private var task: Task<Void, Never>?

  func export(
    note: Note,
    pages: [Page],
    defaultPaperStyle: NotePaperStyle,
    drawingRepository: DrawingRepository
  ) {
    guard task == nil else { return }
    operation = DocumentOperationPresentation(title: "Exporting PDF")
    task = Task {
      do {
        result = try await PDFExportService(drawingRepository: drawingRepository)
          .export(
            note: note,
            pages: pages,
            defaultPaperStyle: defaultPaperStyle,
            onProgress: updateProgress)
        finish(announcement: "PDF export complete")
      } catch PDFExportError.cancelled {
        finish(announcement: "PDF export cancelled")
      } catch {
        task = nil
        operation = nil
        errorMessage = error.localizedDescription
      }
    }
  }

  func cancel() {
    task?.cancel()
  }

  func removeTemporaryResult() {
    guard let url = result?.url else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private func updateProgress(_ progress: Double) {
    guard var operation else { return }
    operation.progress = min(max(progress, 0), 1)
    self.operation = operation
  }

  private func finish(announcement: String) {
    task = nil
    operation = nil
    UIAccessibility.post(notification: .announcement, argument: announcement)
  }
}

struct NoteExportPresentationModifier: ViewModifier {
  @Bindable var controller: NoteExportController

  func body(content: Content) -> some View {
    content
      .sheet(item: $controller.operation) { operation in
        DocumentProgressSheet(operation: operation, onCancel: controller.cancel)
      }
      .sheet(
        item: $controller.result,
        onDismiss: controller.removeTemporaryResult
      ) { result in
        PDFShareSheet(url: result.url)
      }
      .alert("PDF Export", isPresented: errorIsPresented) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(controller.errorMessage ?? "The export couldn't be completed.")
      }
  }

  private var errorIsPresented: Binding<Bool> {
    Binding(
      get: { controller.errorMessage != nil },
      set: { if !$0 { controller.errorMessage = nil } })
  }
}

extension View {
  func noteExportPresentation(_ controller: NoteExportController) -> some View {
    modifier(NoteExportPresentationModifier(controller: controller))
  }
}
