import Foundation
import Testing

@testable import Whyboard

@MainActor
struct ImportPreflightRegressionTests {
  @Test func directImageImportRejectsSparseOversizedSourceBeforeCopy() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let source = directories.root.appending(path: "oversized.png")
    try makeSparseFile(source, byteSize: ResourceLimits.maximumImageSourceBytes + 1)
    let repository = AttachmentRepository(directories: directories)

    await #expect(throws: AttachmentStorageError.self) {
      try await repository.importImage(at: source, noteID: UUID(), pageID: UUID())
    }
    #expect(try directoryIsEmpty(directories.attachments))
  }

  @Test func directPDFImportRejectsSparseOversizedSourceBeforeCopy() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let source = directories.root.appending(path: "oversized.pdf")
    try makeSparseFile(source, byteSize: ResourceLimits.maximumPDFSourceBytes + 1)
    let repository = DocumentRepository(directories: directories)

    await #expect(throws: DocumentStorageError.self) {
      try await repository.importPDF(at: source, noteID: UUID())
    }
    #expect(try directoryIsEmpty(directories.documents))
  }

  @Test func photoTransferRejectsSparseOversizedSourceBeforeTemporaryCopy() throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let source = directories.root.appending(path: "oversized.png")
    try makeSparseFile(source, byteSize: ResourceLimits.maximumImageSourceBytes + 1)

    #expect(throws: AttachmentStorageError.self) {
      try PhotoLibraryTransfer.copiedTransfer(from: source)
    }
  }

  private func makeSparseFile(_ url: URL, byteSize: Int64) throws {
    _ = FileManager.default.createFile(atPath: url.path, contents: Data())
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: UInt64(byteSize))
  }

  private func directoryIsEmpty(_ directory: URL) throws -> Bool {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty
  }
}
