import Foundation
import PencilKit
import SwiftData
import Testing
import UIKit

@testable import Whyboard

extension BackupRestoreTests {
  @Test func backupExcludesDeletedImageRetainedForUndo() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let filename = try #require(
      WorkspaceElementCoding.decode(fixture.page.workspaceElementsData).first?.assetFilename)
    let retainedAttachment = fixture.repository.attachments.fileURL(
      noteID: fixture.note.id,
      pageID: fixture.page.id,
      filename: filename)
    fixture.page.workspaceElementsData = try WorkspaceElementCoding.encode([])
    try fixture.context.save()

    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let manifest = try BackupValidator.validate(package: backup.url)

    #expect(FileManager.default.fileExists(atPath: retainedAttachment.path))
    #expect(!manifest.payloads.contains { $0.relativePath.hasPrefix("attachments/") })
  }

  @Test func backupValidatorRejectsUnlistedEmptyDirectories() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    try FileManager.default.createDirectory(
      at: backup.url.appending(path: "Payload/arbitrary/empty", directoryHint: .isDirectory),
      withIntermediateDirectories: true)

    #expect(throws: BackupValidationError.self) {
      try BackupValidator.validate(package: backup.url)
    }
  }

  @Test func backupRejectsOversizedSourceBeforeCreatingStagingPackage() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let filename = try #require(
      WorkspaceElementCoding.decode(fixture.page.workspaceElementsData).first?.assetFilename)
    let attachment = fixture.repository.attachments.fileURL(
      noteID: fixture.note.id,
      pageID: fixture.page.id,
      filename: filename)
    let handle = try FileHandle(forWritingTo: attachment)
    try handle.truncate(atOffset: UInt64(ResourceLimits.maximumImageSourceBytes + 1))
    try handle.close()

    await #expect(throws: BackupValidationError.self) {
      try await BackupService(drawingRepository: fixture.repository)
        .createBackup(
          folders: fixture.folders,
          notes: [fixture.note],
          pages: [fixture.page],
          importedDocuments: [])
    }
    let backupEntries = try FileManager.default.contentsOfDirectory(
      at: fixture.directories.backups,
      includingPropertiesForKeys: nil)
    #expect(backupEntries.isEmpty)
  }

  @Test func backupCeilingsCoverEveryIndividuallySupportedResourceKind() {
    #expect(ResourceLimits.maximumPayloadBytes >= ResourceLimits.maximumImageSourceBytes)
    #expect(ResourceLimits.maximumPayloadBytes >= ResourceLimits.maximumPDFSourceBytes)
    #expect(ResourceLimits.maximumFolders <= ResourceLimits.maximumManifestEntries)
    #expect(ResourceLimits.maximumNotes <= ResourceLimits.maximumManifestEntries)
    #expect(ResourceLimits.maximumPages <= ResourceLimits.maximumManifestEntries)
    #expect(ResourceLimits.maximumDocuments <= ResourceLimits.maximumManifestEntries)
    #expect(ResourceLimits.maximumPayloadFiles == ResourceLimits.maximumManifestEntries)
    #expect(ResourceLimits.backupWorkingBytes(for: Int64.max) == nil)
  }

  @Test func resourceCountBudgetAcceptsBoundaryAndRejectsAggregateOverflow() throws {
    try BackupValidator.validateResourceCounts(
      BackupCounts(
        folders: 0,
        notes: 0,
        pages: 0,
        importedDocuments: 0,
        payloadFiles: ResourceLimits.maximumManifestEntries))

    #expect(throws: BackupValidationError.self) {
      try BackupValidator.validateResourceCounts(
        BackupCounts(
          folders: 1,
          notes: 0,
          pages: 0,
          importedDocuments: 0,
          payloadFiles: ResourceLimits.maximumManifestEntries))
    }
    #expect(throws: BackupValidationError.self) {
      try BackupValidator.validateResourceCounts(
        BackupCounts(
          folders: -1,
          notes: 0,
          pages: 0,
          importedDocuments: 0,
          payloadFiles: 0))
    }
  }

  @Test func backupSourcePreflightRejectsExcessiveAggregateBytes() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "WhyboardBackupPreflight-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fileCount =
      Int(ResourceLimits.maximumTotalPayloadBytes / ResourceLimits.maximumPDFSourceBytes) + 1
    var sources: [BackupSourceFile] = []
    for index in 0..<fileCount {
      let file = root.appending(path: "\(index).pdf")
      _ = FileManager.default.createFile(atPath: file.path, contents: Data())
      let handle = try FileHandle(forWritingTo: file)
      try handle.truncate(atOffset: UInt64(ResourceLimits.maximumPDFSourceBytes))
      try handle.close()
      sources.append(
        BackupSourceFile(
          url: file,
          relativePath: "documents/\(UUID().uuidString.lowercased())/\(index).pdf"))
    }

    #expect(throws: BackupValidationError.self) {
      try BackupFileUtilities.preflight(sources)
    }
  }

  @Test func backupExcludesOrphanDrawingAndDocumentFiles() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let orphanPageID = UUID()
    let orphanDocumentID = UUID()
    try await fixture.repository.save(
      PKDrawing(),
      pageID: orphanPageID,
      noteID: fixture.note.id)
    let documentDirectory = fixture.repository.documents.rootDirectory
      .appending(
        path: fixture.note.id.uuidString.lowercased(),
        directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: documentDirectory,
      withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(
      to: documentDirectory.appending(
        path: "\(orphanDocumentID.uuidString.lowercased()).pdf"))

    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let manifest = try BackupValidator.validate(package: backup.url)

    #expect(
      !manifest.payloads.contains { $0.relativePath.contains(orphanPageID.uuidString.lowercased()) }
    )
    #expect(
      !manifest.payloads.contains {
        $0.relativePath.contains(orphanDocumentID.uuidString.lowercased())
      })
  }

  @Test func backupValidatorRejectsMalformedReferencedImage() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    try replaceAttachmentPayload(in: backup.url, with: Data("not an image".utf8))

    #expect(throws: AttachmentStorageError.self) {
      try BackupValidator.validate(package: backup.url)
    }
  }

  @Test func backupValidatorRejectsImageWithHostilePixelDimensions() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directories.root) }
    let backup = try await BackupService(drawingRepository: fixture.repository)
      .createBackup(
        folders: fixture.folders,
        notes: [fixture.note],
        pages: [fixture.page],
        importedDocuments: [])
    let validPNG = try #require(
      UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
      }.pngData())
    try replaceAttachmentPayload(
      in: backup.url,
      with: png(validPNG, width: 20_000, height: 20_000))

    #expect(throws: AttachmentStorageError.self) {
      try BackupValidator.validate(package: backup.url)
    }
  }

  @Test func backupHashAndCopyHonorCancellation() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "WhyboardBackupCancellation-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "source")
    try Data(repeating: 42, count: 1_024).write(to: source)

    let hashTask = Task { try BackupFileUtilities.sha256(of: source) }
    hashTask.cancel()
    await #expect(throws: CancellationError.self) { try await hashTask.value }

    let destination = root.appending(path: "destination")
    let copyTask = Task { try BackupFileUtilities.copyFile(from: source, to: destination) }
    copyTask.cancel()
    await #expect(throws: CancellationError.self) { try await copyTask.value }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
  }

  private func replaceAttachmentPayload(in package: URL, with data: Data) throws {
    let manifest = try decodeManifest(at: package)
    let target = try #require(
      manifest.payloads.first { payload in
        BackupFileUtilities.canonicalPayloadRelativePath(payload.relativePath)
          .hasPrefix("attachments/")
      })
    let url = package.appending(path: "Payload").appending(path: target.relativePath)
    try data.write(to: url, options: .atomic)
    let payloads = try manifest.payloads.map { payload in
      guard payload.relativePath == target.relativePath else { return payload }
      return BackupPayload(
        relativePath: payload.relativePath,
        byteSize: Int64(data.count),
        sha256: try BackupFileUtilities.sha256(of: url))
    }
    try writeManifest(
      WhyboardBackupManifest(
        schemaVersion: manifest.schemaVersion,
        appVersion: manifest.appVersion,
        createdAt: manifest.createdAt,
        counts: manifest.counts,
        library: manifest.library,
        payloads: payloads),
      at: package)
  }

  private func png(_ source: Data, width: UInt32, height: UInt32) -> Data {
    var result = source
    result.replaceSubrange(16..<20, with: bigEndianBytes(width))
    result.replaceSubrange(20..<24, with: bigEndianBytes(height))
    let checksum = crc32(result[12..<29])
    result.replaceSubrange(29..<33, with: bigEndianBytes(checksum))
    return result
  }

  private func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    let bigEndian = value.bigEndian
    return withUnsafeBytes(of: bigEndian) { Array($0) }
  }

  private func crc32(_ bytes: Data.SubSequence) -> UInt32 {
    var checksum: UInt32 = 0xffff_ffff
    for byte in bytes {
      checksum ^= UInt32(byte)
      for _ in 0..<8 {
        checksum = (checksum >> 1) ^ (0xedb8_8320 & (0 &- (checksum & 1)))
      }
    }
    return checksum ^ 0xffff_ffff
  }
}
