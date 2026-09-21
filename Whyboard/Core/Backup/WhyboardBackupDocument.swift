import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  nonisolated static let whyboardBackup = UTType(
    exportedAs: "in.kodlabs.whyboard.backup",
    conformingTo: .package)
}

nonisolated struct WhyboardBackupDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.whyboardBackup]

  let packageURL: URL

  init(packageURL: URL) {
    self.packageURL = packageURL
  }

  init(configuration: ReadConfiguration) throws {
    throw BackupValidationError.invalidPackage
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    try FileWrapper(url: packageURL, options: [])
  }
}
