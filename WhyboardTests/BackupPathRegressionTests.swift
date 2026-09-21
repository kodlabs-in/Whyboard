import Foundation
import SwiftData
import Testing

@testable import Whyboard

extension BackupRestoreTests {
  @Test func relativePayloadPathNormalizesIOSPrivateVarAlias() {
    let root = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/TEST/Drawings")
    let file = URL(
      fileURLWithPath:
        "/private/var/mobile/Containers/Data/Application/TEST/Drawings/note/page.drawing")

    #expect(BackupFileUtilities.relativePath(of: file, under: root) == "note/page.drawing")
  }

  @Test func restoreRepairsPayloadPathsWrittenWithIOSPrivateVarAliasBug() async throws {
    let source = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: source.directories.root) }
    let backup = try await BackupService(drawingRepository: source.repository)
      .createBackup(
        folders: source.folders,
        notes: [source.note],
        pages: [source.page],
        importedDocuments: [])
    let original = try decodeManifest(at: backup.url)
    try rewritePayloadsWithLegacyAliases(original, package: backup.url)

    let fresh = try makeFreshInstallation()
    defer { try? FileManager.default.removeItem(at: fresh.directories.root) }
    let result = try await RestoreService(drawingRepository: fresh.repository)
      .restore(
        from: backup.url,
        existingFolders: [fresh.rootFolder],
        context: fresh.context)
    let restoredNote = try #require(fresh.context.fetch(FetchDescriptor<Note>()).first)
    let restoredPage = try #require(fresh.context.fetch(FetchDescriptor<Page>()).first)
    let attachment = try #require(
      WorkspaceElementCoding.decode(restoredPage.workspaceElementsData).first?.assetFilename)

    #expect(result.notes == 1)
    #expect(result.pages == 1)
    #expect(
      FileManager.default.fileExists(
        atPath: fresh.repository.attachments.fileURL(
          noteID: restoredNote.id,
          pageID: restoredPage.id,
          filename: attachment
        ).path))
    _ = try await fresh.repository.load(pageID: restoredPage.id, noteID: restoredNote.id)
  }

  private func rewritePayloadsWithLegacyAliases(
    _ manifest: WhyboardBackupManifest,
    package: URL
  ) throws {
    let aliases = [
      "drawings": "rawings",
      "attachments": "chments",
      "documents": "cuments",
    ]
    let payloadRoot = package.appending(path: "Payload", directoryHint: .isDirectory)
    let payloads = try manifest.payloads.map { payload in
      let components = payload.relativePath.split(separator: "/").map(String.init)
      let category = try #require(components.first)
      let alias = try #require(aliases[category])
      let legacyPath = ([category, alias] + components.dropFirst()).joined(separator: "/")
      let destination = payloadRoot.appending(path: legacyPath)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try FileManager.default.moveItem(
        at: payloadRoot.appending(path: payload.relativePath),
        to: destination)
      return BackupPayload(
        relativePath: legacyPath,
        byteSize: payload.byteSize,
        sha256: payload.sha256)
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
}
