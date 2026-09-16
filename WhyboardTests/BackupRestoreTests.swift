import PencilKit
import SwiftData
import Testing

@testable import Whyboard

@MainActor
struct BackupRestoreTests {
  @Test func backupManifestIsVersionedChecksummedAndExcludesPreviews() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }

    let result = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let manifest = try BackupValidator.validate(package: result.url)

    #expect(manifest.schemaVersion == WhyboardBackupManifest.currentSchemaVersion)
    #expect(manifest.counts.notes == 1)
    #expect(manifest.counts.pages == 1)
    #expect(manifest.payloads.contains { $0.relativePath.hasPrefix("drawings/") })
    #expect(manifest.payloads.contains { $0.relativePath.hasPrefix("attachments/") })
    #expect(!manifest.payloads.contains { $0.relativePath.contains("previews") })
    #expect(manifest.payloads.allSatisfy { $0.sha256.count == 64 })
  }

  @Test func restoreKeepsBothAndRemapsEveryIdentity() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let sourceIDs: Set<UUID> = [fixture.note.id, fixture.page.id]

    let restored = try await RestoreService(drawingRepository: fixture.repository)
      .restore(
        from: backup.url,
        existingFolders: fixture.folders,
        context: fixture.context)
    let notes = try fixture.context.fetch(FetchDescriptor<Note>())
    let pages = try fixture.context.fetch(FetchDescriptor<Page>())
    let restoredIDs = Set(notes.map(\.id) + pages.map(\.id)).subtracting(sourceIDs)

    #expect(restored.notes == 1)
    #expect(restored.pages == 1)
    #expect(notes.count == 2)
    #expect(pages.count == 2)
    #expect(restoredIDs.count == 2)
  }

  @Test func checksumFailureLeavesLibraryUnchanged() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let manifest = try decodeManifest(at: backup.url)
    let payload = try #require(manifest.payloads.first)
    let payloadURL = backup.url.appending(path: "Payload").appending(path: payload.relativePath)
    try Data([0, 1, 2, 3]).write(to: payloadURL, options: .atomic)

    await #expect(throws: BackupFileError.self) {
      try await RestoreService(drawingRepository: fixture.repository)
        .restore(
          from: backup.url,
          existingFolders: fixture.folders,
          context: fixture.context)
    }
    #expect(try fixture.context.fetchCount(FetchDescriptor<Note>()) == 1)
    #expect(try fixture.context.fetchCount(FetchDescriptor<Page>()) == 1)
  }

  @Test func validatorRejectsTraversalAndFutureSchema() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let original = try decodeManifest(at: backup.url)
    let first = try #require(original.payloads.first)
    let unsafePayload = BackupPayload(
      relativePath: "../\(first.relativePath)",
      byteSize: first.byteSize,
      sha256: first.sha256)
    let unsafe = WhyboardBackupManifest(
      schemaVersion: original.schemaVersion,
      appVersion: original.appVersion,
      createdAt: original.createdAt,
      counts: original.counts,
      library: original.library,
      payloads: [unsafePayload] + original.payloads.dropFirst())
    try writeManifest(unsafe, at: backup.url)
    #expect(throws: BackupFileError.self) {
      try BackupValidator.validate(package: backup.url)
    }

    let future = WhyboardBackupManifest(
      schemaVersion: WhyboardBackupManifest.currentSchemaVersion + 1,
      appVersion: original.appVersion,
      createdAt: original.createdAt,
      counts: original.counts,
      library: original.library,
      payloads: original.payloads)
    try writeManifest(future, at: backup.url)
    #expect(throws: BackupValidationError.self) {
      try BackupValidator.validate(package: backup.url)
    }
  }

  @Test func missingPayloadIsRejectedBeforeRestoreMutation() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let manifest = try decodeManifest(at: backup.url)
    let payload = try #require(manifest.payloads.first)
    try FileManager.default.removeItem(
      at: backup.url.appending(path: "Payload").appending(path: payload.relativePath))

    await #expect(throws: BackupFileError.self) {
      try await RestoreService(drawingRepository: fixture.repository)
        .restore(
          from: backup.url,
          existingFolders: fixture.folders,
          context: fixture.context)
    }
    #expect(try fixture.context.fetchCount(FetchDescriptor<Note>()) == 1)
    #expect(try fixture.context.fetchCount(FetchDescriptor<Page>()) == 1)
  }

  @Test func cancelledBackupPublishesNoPackage() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let operation = Task {
      try await BackupService(drawingRepository: fixture.repository)
        .createBackup(
          folders: fixture.folders,
          notes: [fixture.note],
          pages: [fixture.page],
          importedDocuments: [])
    }
    operation.cancel()

    await #expect(throws: BackupCreationError.self) {
      try await operation.value
    }
    let packages = try FileManager.default.contentsOfDirectory(
      at: fixture.directories.backups,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "whyboardbackup" && !$0.lastPathComponent.hasPrefix(".") }
    #expect(packages.isEmpty)
  }

  @Test func cancelledRestoreLeavesExistingLibraryUnchanged() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let operation = Task {
      try await RestoreService(drawingRepository: fixture.repository)
        .restore(
          from: backup.url,
          existingFolders: fixture.folders,
          context: fixture.context)
    }
    operation.cancel()

    await #expect(throws: RestoreError.self) {
      try await operation.value
    }
    #expect(try fixture.context.fetchCount(FetchDescriptor<Note>()) == 1)
    #expect(try fixture.context.fetchCount(FetchDescriptor<Page>()) == 1)
  }

  private func makeFixture() async throws -> BackupFixture {
    let schema = Schema([Folder.self, Note.self, Page.self, ImportedDocument.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = container.mainContext
    let directories = try AppDirectories.makeForTesting()
    let repository = DrawingRepository(directories: directories)
    let root = Folder(name: "Library", isSystem: true)
    let folder = Folder(name: "Projects")
    let note = Note(folderID: folder.id, title: "Architecture")
    let page = Page(noteID: note.id, sortOrder: 0)
    [root, folder].forEach(context.insert)
    context.insert(note)
    context.insert(page)
    try await repository.save(PKDrawing(), pageID: page.id, noteID: note.id)
    let source = directories.root.appending(path: "fixture.png")
    try Data([10, 20, 30]).write(to: source)
    let filename = try await repository.attachments.importFile(
      at: source,
      noteID: note.id,
      pageID: page.id)
    page.workspaceElementsData = try WorkspaceElementCoding.encode([
      WorkspaceElement(
        kind: .image,
        frame: WorkspaceElementFrame(
          center: CGPoint(x: 100, y: 100),
          size: CGSize(width: 80, height: 60)),
        zIndex: 0,
        assetFilename: filename)
    ])
    try context.save()
    return BackupFixture(
      container: container,
      context: context,
      directories: directories,
      repository: repository,
      folders: [root, folder],
      note: note,
      page: page)
  }

  private func decodeManifest(at package: URL) throws -> WhyboardBackupManifest {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      WhyboardBackupManifest.self,
      from: Data(contentsOf: package.appending(path: "manifest.json")))
  }

  private func writeManifest(_ manifest: WhyboardBackupManifest, at package: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(
      to: package.appending(path: "manifest.json"),
      options: .atomic)
  }
}

@MainActor
private struct BackupFixture {
  // A ModelContext does not retain its container. Keep the container alive for
  // the complete test so SwiftData cannot invalidate the fixture's models.
  let container: ModelContainer
  let context: ModelContext
  let directories: AppDirectories
  let repository: DrawingRepository
  let folders: [Folder]
  let note: Note
  let page: Page
}
