import PDFKit
import SwiftData
import Testing
import UIKit

@testable import Whyboard

private actor SuspendedImageStore {
  private var didStart = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func store() async -> StoredImageAttachment {
    didStart = true
    let waiters = startWaiters
    startWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { releaseWaiter = $0 }
    return StoredImageAttachment(filename: "stored.jpg", aspectRatio: 1.5)
  }

  func waitUntilStarted() async {
    if didStart { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release() {
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}

@MainActor
struct ResourceSafetyTests {
  @Test func imageImportValidatesBeforePublishingAndLeavesNoPartialFile() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = AttachmentRepository(directories: directories)
    let noteID = UUID()
    let pageID = UUID()
    let validSource = directories.root.appending(path: "valid.jpg")
    let invalidSource = directories.root.appending(path: "invalid.jpg")
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20))
    let image = renderer.image { context in
      UIColor.orange.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    }
    try #require(image.jpegData(compressionQuality: 0.8)).write(to: validSource)
    try Data("not an image".utf8).write(to: invalidSource)

    let stored = try await repository.importImage(
      at: validSource,
      noteID: noteID,
      pageID: pageID)
    #expect(stored.aspectRatio == 2)

    await #expect(throws: AttachmentStorageError.self) {
      try await repository.importImage(
        at: invalidSource,
        noteID: noteID,
        pageID: pageID)
    }
    let pageDirectory = repository.fileURL(
      noteID: noteID,
      pageID: pageID,
      filename: stored.filename
    ).deletingLastPathComponent()
    let files = try FileManager.default.contentsOfDirectory(
      at: pageDirectory,
      includingPropertiesForKeys: nil)
    #expect(files.map(\.lastPathComponent) == [stored.filename])
  }

  @Test func mediaImportKeepsItsOriginalPageAndRejectsAnOverlappingImport() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let source = directories.root.appending(path: "photo.jpg")
    let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { context in
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
    }
    try #require(image.jpegData(compressionQuality: 0.8)).write(to: source)
    let store = SuspendedImageStore()
    let controller = MediaImportController(
      attachments: AttachmentRepository(directories: directories),
      imageStore: { _, _, _ in await store.store() })
    let noteID = UUID()
    let firstPageID = UUID()
    let secondPageID = UUID()
    var importedPageID: UUID?
    var messages: [String] = []
    controller.configure(
      noteID: noteID,
      onImported: { pageID, _ in
        importedPageID = pageID
        return true
      },
      onError: { messages.append($0) })
    controller.presentFileImporter(for: firstPageID)

    let importTask = Task { await controller.importFile(.success(source)) }
    await store.waitUntilStarted()
    controller.presentFileImporter(for: secondPageID)
    await store.release()
    await importTask.value

    #expect(importedPageID == firstPageID)
    #expect(messages.contains { $0.contains("current photo import") })
  }

  @Test func mediaImporterReportsProviderFailuresButNotExplicitCancellation() async throws {
    struct ProviderFailure: LocalizedError {
      var errorDescription: String? { "Provider failed" }
    }

    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let controller = MediaImportController(
      attachments: AttachmentRepository(directories: directories))
    var messages: [String] = []
    controller.configure(
      noteID: UUID(),
      onImported: { _, _ in true },
      onError: { messages.append($0) })
    controller.presentFileImporter(for: UUID())
    await controller.importFile(.failure(ProviderFailure()))
    #expect(messages == ["Provider failed"])

    controller.isFileImporterPresented = false
    controller.presentFileImporter(for: UUID())
    await controller.importFile(.failure(CancellationError()))
    #expect(messages == ["Provider failed"])
  }

  @Test func rejectedImageInsertionRemovesTheStoredAttachment() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let source = directories.root.appending(path: "orphan.jpg")
    let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
      UIColor.orange.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
    }
    try #require(image.jpegData(compressionQuality: 0.8)).write(to: source)

    let attachments = AttachmentRepository(directories: directories)
    let noteID = UUID()
    let pageID = UUID()
    let controller = MediaImportController(attachments: attachments)
    controller.configure(
      noteID: noteID,
      onImported: { _, _ in false },
      onError: { _ in })
    controller.presentFileImporter(for: pageID)

    await controller.importFile(.success(source))

    let destinationDirectory = attachments.fileURL(
      noteID: noteID,
      pageID: pageID,
      filename: "unused"
    ).deletingLastPathComponent()
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: destinationDirectory,
        includingPropertiesForKeys: nil)) ?? []
    #expect(files.isEmpty)
  }
}

extension BackupRestoreTests {
  @Test func backupValidatorRejectsUnlistedFilesAndSymbolicLinks() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let unexpected = backup.url.appending(path: "unlisted")
    try FileManager.default.createSymbolicLink(
      at: unexpected,
      withDestinationURL: backup.url.appending(path: "manifest.json"))

    #expect(throws: BackupValidationError.self) {
      try BackupValidator.validate(package: backup.url)
    }
  }

  @Test func backupValidatorRejectsMalformedWorkspaceDataWithoutLossyRecovery() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let manifest = try decodeManifest(at: backup.url)
    let originalPage = try #require(manifest.library.pages.first)
    let malformedPage = BackupPageRecord(
      id: originalPage.id,
      noteID: originalPage.noteID,
      sortOrder: originalPage.sortOrder,
      contentRevision: originalPage.contentRevision,
      createdAt: originalPage.createdAt,
      updatedAt: originalPage.updatedAt,
      workspaceElementsData: Data("[{\"kind\":\"image\"}]".utf8),
      importedDocumentID: originalPage.importedDocumentID,
      importedDocumentPageIndex: originalPage.importedDocumentPageIndex)
    let malformedLibrary = BackupLibrary(
      folders: manifest.library.folders,
      notes: manifest.library.notes,
      pages: [malformedPage],
      importedDocuments: manifest.library.importedDocuments)
    try writeManifest(
      WhyboardBackupManifest(
        schemaVersion: manifest.schemaVersion,
        appVersion: manifest.appVersion,
        createdAt: manifest.createdAt,
        counts: manifest.counts,
        library: malformedLibrary,
        payloads: manifest.payloads),
      at: backup.url)

    #expect(throws: BackupValidationError.self) {
      try BackupValidator.validate(package: backup.url)
    }
  }
}
