import Foundation

enum BackupCreationError: LocalizedError {
  case sourceSaveFailed
  case cancelled
  case manifestWriteFailed

  var errorDescription: String? {
    switch self {
    case .sourceSaveFailed:
      "Save all open notes before creating a backup."
    case .cancelled:
      "Backup creation was cancelled."
    case .manifestWriteFailed:
      "Whyboard couldn't finish the backup manifest."
    }
  }
}

private nonisolated struct BackupPackageInput: Sendable {
  let library: BackupLibrary
  let counts: BackupCounts
  let noteIDs: Set<UUID>
  let appVersion: String
}

private actor BackupPackageWorker {
  let drawingRepository: DrawingRepository

  init(drawingRepository: DrawingRepository) {
    self.drawingRepository = drawingRepository
  }

  func createPackage(
    input: BackupPackageInput,
    progress: AsyncStream<Double>.Continuation
  ) throws -> BackupExportResult {
    let staging = stagingURL()
    do {
      try Task.checkCancellation()
      let sourceFiles = BackupFileUtilities.sourceFiles(
        noteIDs: input.noteIDs,
        drawingRepository: drawingRepository)
      try verifyAvailableStorage(for: sourceFiles)
      try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
      let payloads = try copyPayloads(sourceFiles, to: staging, progress: progress)
      try Task.checkCancellation()
      let counts = BackupCounts(
        folders: input.counts.folders,
        notes: input.counts.notes,
        pages: input.counts.pages,
        importedDocuments: input.counts.importedDocuments,
        payloadFiles: payloads.count)
      try writeManifest(
        library: input.library,
        counts: counts,
        payloads: payloads,
        appVersion: input.appVersion,
        to: staging)
      try Task.checkCancellation()
      let destination = backupURL()
      try FileManager.default.moveItem(at: staging, to: destination)
      progress.yield(1)
      return BackupExportResult(url: destination, counts: counts)
    } catch {
      try? FileManager.default.removeItem(at: staging)
      throw error
    }
  }

  private func copyPayloads(
    _ files: [BackupSourceFile],
    to package: URL,
    progress: AsyncStream<Double>.Continuation
  ) throws -> [BackupPayload] {
    try files.enumerated().map { index, source in
      let interval = AppSignpost.interval("Backup Item")
      defer { interval.end() }
      try Task.checkCancellation()
      guard BackupFileUtilities.isSafeRelativePath(source.relativePath) else {
        throw BackupFileError.unsafePath
      }
      let destination =
        package
        .appending(path: "Payload", directoryHint: .isDirectory)
        .appending(path: source.relativePath)
      try BackupFileUtilities.copyFile(from: source.url, to: destination)
      let payload = BackupPayload(
        relativePath: source.relativePath,
        byteSize: try BackupFileUtilities.byteSize(of: destination),
        sha256: try BackupFileUtilities.sha256(of: destination))
      progress.yield(Double(index + 1) / Double(max(files.count + 1, 1)))
      return payload
    }
  }

  private func writeManifest(
    library: BackupLibrary,
    counts: BackupCounts,
    payloads: [BackupPayload],
    appVersion: String,
    to package: URL
  ) throws {
    let manifest = WhyboardBackupManifest(
      schemaVersion: WhyboardBackupManifest.currentSchemaVersion,
      appVersion: appVersion,
      createdAt: Date(),
      counts: counts,
      library: library,
      payloads: payloads)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try encoder.encode(manifest)
      try data.write(
        to: package.appending(path: "manifest.json"),
        options: [.atomic, .completeFileProtection])
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: package.path)
    } catch {
      throw BackupCreationError.manifestWriteFailed
    }
  }

  private func verifyAvailableStorage(for files: [BackupSourceFile]) throws {
    let required = try files.reduce(Int64(5_000_000)) { total, file in
      let size = try BackupFileUtilities.byteSize(of: file.url)
      return total + size
    }
    let values = try drawingRepository.backupsDirectory.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
    guard available > required * 2 else { throw BackupFileError.insufficientStorage }
  }

  private func stagingURL() -> URL {
    drawingRepository.backupsDirectory
      .appending(
        path: ".staging-\(UUID().uuidString).whyboardbackup",
        directoryHint: .isDirectory)
  }

  private func backupURL() -> URL {
    let timestamp = ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let suffix = UUID().uuidString.prefix(8)
    return drawingRepository.backupsDirectory
      .appending(
        path: "Whyboard \(timestamp) \(suffix).whyboardbackup",
        directoryHint: .isDirectory)
  }
}

@MainActor
struct BackupService {
  let drawingRepository: DrawingRepository

  func createBackup(
    folders: [Folder],
    notes: [Note],
    pages: [Page],
    importedDocuments: [ImportedDocument],
    onProgress: @escaping (Double) -> Void = { _ in }
  ) async throws -> BackupExportResult {
    guard await drawingRepository.pendingSaves.flushAll(noteIDs: notes.map(\.id)) else {
      throw BackupCreationError.sourceSaveFailed
    }
    let input = BackupPackageInput(
      library: BackupLibrary(
        folders: folders,
        notes: notes,
        pages: pages,
        importedDocuments: importedDocuments),
      counts: BackupCounts(
        folders: folders.count,
        notes: notes.count,
        pages: pages.count,
        importedDocuments: importedDocuments.count,
        payloadFiles: 0),
      noteIDs: Set(notes.map(\.id)),
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1")
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
      return try await BackupPackageWorker(drawingRepository: drawingRepository)
        .createPackage(input: input, progress: continuation)
    } catch is CancellationError {
      throw BackupCreationError.cancelled
    }
  }
}
