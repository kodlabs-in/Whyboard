import Foundation
import SwiftData

enum RestoreError: LocalizedError {
  case missingLibraryRoot
  case publishFailed
  case cancelled

  var errorDescription: String? {
    switch self {
    case .missingLibraryRoot:
      "Whyboard couldn't find the Library destination."
    case .publishFailed:
      "Whyboard couldn't publish the restored library. Your current library is unchanged."
    case .cancelled:
      "Backup restore was cancelled."
    }
  }
}

private nonisolated struct RestoreIdentityMap: Sendable {
  let folders: [UUID: UUID]
  let notes: [UUID: UUID]
  let pages: [UUID: UUID]
  let documents: [UUID: UUID]
}

private nonisolated struct PreparedRestorePackage: Sendable {
  let staging: URL
  let manifest: WhyboardBackupManifest
}

private actor RestorePackageWorker {
  let drawingRepository: DrawingRepository

  init(drawingRepository: DrawingRepository) {
    self.drawingRepository = drawingRepository
  }

  func prepare(source: URL) throws -> PreparedRestorePackage {
    let staging = drawingRepository.backupsDirectory
      .appending(
        path: ".restore-\(UUID().uuidString).whyboardbackup",
        directoryHint: .isDirectory)
    let didAccess = source.startAccessingSecurityScopedResource()
    defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
    do {
      try Task.checkCancellation()
      try FileManager.default.copyItem(at: source, to: staging)
      let manifest = try BackupValidator.validate(package: staging)
      return PreparedRestorePackage(staging: staging, manifest: manifest)
    } catch {
      try? FileManager.default.removeItem(at: staging)
      throw error
    }
  }

  func copyPayloads(
    _ payloads: [BackupPayload],
    package: URL,
    identityMap: RestoreIdentityMap,
    progress: AsyncStream<Double>.Continuation
  ) throws {
    for (index, payload) in payloads.enumerated() {
      try Task.checkCancellation()
      let source = package.appending(path: "Payload").appending(path: payload.relativePath)
      let destination = try destinationURL(
        for: BackupFileUtilities.canonicalPayloadRelativePath(payload.relativePath),
        identityMap: identityMap)
      try BackupFileUtilities.copyFile(from: source, to: destination)
      progress.yield(Double(index + 1) / Double(max(payloads.count + 1, 1)))
    }
  }

  func discard(_ package: URL) {
    try? FileManager.default.removeItem(at: package)
  }

  func cleanup(noteIDs: Set<UUID>) {
    for noteID in noteIDs {
      let component = noteID.uuidString.lowercased()
      try? FileManager.default.removeItem(
        at: drawingRepository.drawingsDirectory.appending(path: component))
      try? FileManager.default.removeItem(
        at: drawingRepository.attachments.rootDirectory.appending(path: component))
      try? FileManager.default.removeItem(
        at: drawingRepository.documents.rootDirectory.appending(path: component))
    }
  }

  private func destinationURL(
    for relativePath: String,
    identityMap: RestoreIdentityMap
  ) throws -> URL {
    let components = relativePath.split(separator: "/").map(String.init)
    guard let category = components.first else { throw BackupFileError.unsafePath }
    switch category {
    case "drawings":
      return try drawingDestination(components, identityMap: identityMap)
    case "attachments":
      return try attachmentDestination(components, identityMap: identityMap)
    case "documents":
      return try documentDestination(components, identityMap: identityMap)
    default:
      throw BackupFileError.unsafePath
    }
  }

  private func drawingDestination(
    _ components: [String],
    identityMap: RestoreIdentityMap
  ) throws -> URL {
    guard
      components.count == 3,
      let oldNoteID = UUID(uuidString: components[1]),
      let oldPageID = UUID(
        uuidString: URL(fileURLWithPath: components[2]).deletingPathExtension().lastPathComponent),
      let noteID = identityMap.notes[oldNoteID],
      let pageID = identityMap.pages[oldPageID]
    else { throw BackupFileError.unsafePath }
    return drawingRepository.drawingsDirectory
      .appending(path: noteID.uuidString.lowercased())
      .appending(path: "\(pageID.uuidString.lowercased()).drawing")
  }

  private func attachmentDestination(
    _ components: [String],
    identityMap: RestoreIdentityMap
  ) throws -> URL {
    guard
      components.count == 4,
      let oldNoteID = UUID(uuidString: components[1]),
      let oldPageID = UUID(uuidString: components[2]),
      let noteID = identityMap.notes[oldNoteID],
      let pageID = identityMap.pages[oldPageID]
    else { throw BackupFileError.unsafePath }
    return drawingRepository.attachments.fileURL(
      noteID: noteID,
      pageID: pageID,
      filename: components[3])
  }

  private func documentDestination(
    _ components: [String],
    identityMap: RestoreIdentityMap
  ) throws -> URL {
    guard
      components.count == 3,
      let oldNoteID = UUID(uuidString: components[1]),
      let oldDocumentID = UUID(
        uuidString: URL(fileURLWithPath: components[2]).deletingPathExtension().lastPathComponent),
      let noteID = identityMap.notes[oldNoteID],
      let documentID = identityMap.documents[oldDocumentID]
    else { throw BackupFileError.unsafePath }
    return drawingRepository.documents.fileURL(noteID: noteID, documentID: documentID)
  }
}

@MainActor
struct RestoreService {
  let drawingRepository: DrawingRepository

  func restore(
    from source: URL,
    existingFolders: [Folder],
    context: ModelContext,
    onProgress: @escaping (Double) -> Void = { _ in }
  ) async throws -> RestoreResult {
    let worker = RestorePackageWorker(drawingRepository: drawingRepository)
    let (progress, continuation) = AsyncStream<Double>.makeStream()
    let progressTask = Task {
      for await value in progress {
        onProgress(value)
      }
    }
    var prepared: PreparedRestorePackage?
    var restoredNoteIDs: Set<UUID> = []
    defer {
      continuation.finish()
      progressTask.cancel()
    }

    do {
      let package = try await worker.prepare(source: source)
      prepared = package
      let manifest = package.manifest
      let identityMap = try makeIdentityMap(
        library: manifest.library,
        existingFolders: existingFolders)
      restoredNoteIDs = Set(identityMap.notes.values)
      try await worker.copyPayloads(
        manifest.payloads,
        package: package.staging,
        identityMap: identityMap,
        progress: continuation)
      try Task.checkCancellation()
      let result = try publish(
        library: manifest.library,
        identityMap: identityMap,
        context: context)
      continuation.yield(1)
      await worker.discard(package.staging)
      return result
    } catch is CancellationError {
      await worker.cleanup(noteIDs: restoredNoteIDs)
      if let prepared { await worker.discard(prepared.staging) }
      throw RestoreError.cancelled
    } catch {
      await worker.cleanup(noteIDs: restoredNoteIDs)
      if let prepared { await worker.discard(prepared.staging) }
      throw error
    }
  }

  private func makeIdentityMap(
    library: BackupLibrary,
    existingFolders: [Folder]
  ) throws -> RestoreIdentityMap {
    guard let rootID = existingFolders.first(where: \.isSystem)?.id else {
      throw RestoreError.missingLibraryRoot
    }
    let folderMap = Dictionary(
      uniqueKeysWithValues: library.folders.map { folder in
        (folder.id, folder.isSystem ? rootID : UUID())
      })
    return RestoreIdentityMap(
      folders: folderMap,
      notes: newIDs(for: library.notes.map(\.id)),
      pages: newIDs(for: library.pages.map(\.id)),
      documents: newIDs(for: library.importedDocuments.map(\.id)))
  }

  private func newIDs(for sourceIDs: [UUID]) -> [UUID: UUID] {
    Dictionary(uniqueKeysWithValues: sourceIDs.map { ($0, UUID()) })
  }

  private func publish(
    library: BackupLibrary,
    identityMap: RestoreIdentityMap,
    context: ModelContext
  ) throws -> RestoreResult {
    library.folders.filter { !$0.isSystem }.map {
      restoredFolder($0, identityMap: identityMap)
    }.forEach(context.insert)
    library.notes.map { restoredNote($0, identityMap: identityMap) }.forEach(context.insert)
    library.pages.map { restoredPage($0, identityMap: identityMap) }.forEach(context.insert)
    library.importedDocuments.map {
      restoredDocument($0, identityMap: identityMap)
    }.forEach(context.insert)
    do {
      try context.save()
      return RestoreResult(
        folders: library.folders.filter { !$0.isSystem }.count,
        notes: library.notes.count,
        pages: library.pages.count)
    } catch {
      context.rollback()
      throw RestoreError.publishFailed
    }
  }

  private func restoredFolder(
    _ record: BackupFolderRecord,
    identityMap: RestoreIdentityMap
  ) -> Folder {
    Folder(
      id: identityMap.folders[record.id] ?? UUID(),
      parentFolderID: record.parentFolderID.flatMap { identityMap.folders[$0] },
      name: record.name,
      sortOrder: record.sortOrder,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt)
  }

  private func restoredNote(
    _ record: BackupNoteRecord,
    identityMap: RestoreIdentityMap
  ) -> Note {
    let storedDefault =
      NotePaperStyle(
        rawValue: AppPreferences.store.string(forKey: NotePaperStyle.defaultStorageKey) ?? ""
      ) ?? .defaultStyle
    let restoredPaperStyle =
      NotePaperStyle(rawValue: record.paperStyleRawValue ?? "")
      ?? (storedDefault == .automatic ? .defaultStyle : storedDefault)
    let note = Note(
      id: identityMap.notes[record.id] ?? UUID(),
      folderID: identityMap.folders[record.folderID] ?? UUID(),
      title: record.title,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      lastOpenedAt: record.lastOpenedAt,
      lastScrollOffset: record.lastScrollOffset,
      paperStyle: restoredPaperStyle,
      kind: NoteKind(rawValue: record.noteKindRawValue ?? "") ?? .infinitePages,
      isFavorite: record.isFavorite)
    note.canvasOffsetX = record.canvasOffsetX
    note.canvasOffsetY = record.canvasOffsetY
    note.canvasZoomScale = record.canvasZoomScale
    return note
  }

  private func restoredPage(
    _ record: BackupPageRecord,
    identityMap: RestoreIdentityMap
  ) -> Page {
    let page = Page(
      id: identityMap.pages[record.id] ?? UUID(),
      noteID: identityMap.notes[record.noteID] ?? UUID(),
      sortOrder: record.sortOrder,
      contentRevision: record.contentRevision,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt)
    page.workspaceElementsData = record.workspaceElementsData
    page.importedDocumentID = record.importedDocumentID.flatMap { identityMap.documents[$0] }
    page.importedDocumentPageIndex = record.importedDocumentPageIndex
    return page
  }

  private func restoredDocument(
    _ record: BackupDocumentRecord,
    identityMap: RestoreIdentityMap
  ) -> ImportedDocument {
    ImportedDocument(
      id: identityMap.documents[record.id] ?? UUID(),
      noteID: identityMap.notes[record.noteID] ?? UUID(),
      pageCount: record.pageCount,
      createdAt: record.createdAt,
      formatVersion: record.formatVersion)
  }

}
