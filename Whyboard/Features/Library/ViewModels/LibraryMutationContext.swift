import SwiftData

struct LibraryMutationContext {
  let folders: [Folder]
  let notes: [Note]
  let pages: [Page]
  let importedDocuments: [ImportedDocument]
  let modelContext: ModelContext
  let drawingRepository: DrawingRepository
}
