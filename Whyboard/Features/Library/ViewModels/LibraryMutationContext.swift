import SwiftData

struct LibraryMutationContext {
  let folders: [Folder]
  let notes: [Note]
  let pages: [Page]
  let modelContext: ModelContext
  let drawingRepository: DrawingRepository
}
