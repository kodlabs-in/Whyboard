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
      let referencedAttachmentPaths = try BackupValidator.referencedAttachmentPaths(
        in: input.library)
      let sourceFiles = BackupFileUtilities.sourceFiles(
        library: input.library,
        referencedAttachmentPaths: referencedAttachmentPaths,
        drawingRepository: drawingRepository)
      let sourcePreflight = try BackupFileUtilities.preflight(sourceFiles)
      try BackupValidator.validateResourceCounts(
        BackupCounts(
          folders: input.counts.folders,
          notes: input.counts.notes,
          pages: input.counts.pages,
          importedDocuments: input.counts.importedDocuments,
          payloadFiles: sourceFiles.count))
      try verifyAvailableStorage(payloadBytes: sourcePreflight.totalBytes)
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
      _ = try BackupValidator.validate(package: staging)
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
    var payloads: [BackupPayload] = []
    payloads.reserveCapacity(files.count)
    var copiedBytes: Int64 = 0
    for (index, source) in files.enumerated() {
      try Task.checkCancellation()
      guard BackupFileUtilities.isSafeRelativePath(source.relativePath) else {
        throw BackupFileError.unsafePath
      }
      let destination =
        package
        .appending(path: "Payload", directoryHint: .isDirectory)
        .appending(path: source.relativePath)
      try BackupFileUtilities.copyFile(from: source.url, to: destination)
      let byteSize = try BackupFileUtilities.byteSize(of: destination)
      guard byteSize <= BackupFileUtilities.maximumPayloadBytes(for: source.relativePath) else {
        throw BackupValidationError.resourceLimitExceeded
      }
      let (nextTotal, overflow) = copiedBytes.addingReportingOverflow(byteSize)
      guard !overflow, nextTotal <= ResourceLimits.maximumTotalPayloadBytes else {
        throw BackupValidationError.resourceLimitExceeded
      }
      copiedBytes = nextTotal
      let payload = BackupPayload(
        relativePath: source.relativePath,
        byteSize: byteSize,
        sha256: try BackupFileUtilities.sha256(of: destination))
      payloads.append(payload)
      progress.yield(Double(index + 1) / Double(max(files.count + 1, 1)))
    }
    return payloads
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

  private func verifyAvailableStorage(payloadBytes: Int64) throws {
    guard let required = ResourceLimits.backupWorkingBytes(for: payloadBytes) else {
      throw BackupValidationError.resourceLimitExceeded
    }
    let values = try drawingRepository.backupsDirectory.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
    guard available >= required else { throw BackupFileError.insufficientStorage }
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
