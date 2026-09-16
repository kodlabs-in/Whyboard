import Foundation

enum BackupValidationError: LocalizedError {
  case invalidPackage
  case unsupportedVersion
  case countMismatch
  case duplicateIdentifier
  case duplicatePayload
  case invalidReference

  var errorDescription: String? {
    switch self {
    case .invalidPackage:
      "This isn't a valid Whyboard backup."
    case .unsupportedVersion:
      "This backup was created by a newer, unsupported Whyboard version."
    case .countMismatch:
      "The backup's recorded item counts do not match its contents."
    case .duplicateIdentifier:
      "The backup contains duplicate item identifiers."
    case .duplicatePayload:
      "The backup lists the same payload more than once."
    case .invalidReference:
      "The backup contains an invalid note, page, attachment, or PDF reference."
    }
  }
}

nonisolated enum BackupValidator {
  static func validate(package: URL) throws -> WhyboardBackupManifest {
    let manifest = try decodeManifest(package: package)
    try validateVersion(manifest.schemaVersion)
    try validateCounts(manifest)
    try validateIdentifiers(manifest.library)
    try validateReferences(manifest.library, payloads: manifest.payloads)
    try validatePayloads(manifest.payloads, package: package)
    return manifest
  }

  private static func decodeManifest(package: URL) throws -> WhyboardBackupManifest {
    guard package.pathExtension.lowercased() == "whyboardbackup" else {
      throw BackupValidationError.invalidPackage
    }
    do {
      let data = try Data(contentsOf: package.appending(path: "manifest.json"))
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(WhyboardBackupManifest.self, from: data)
    } catch let error as BackupValidationError {
      throw error
    } catch {
      throw BackupValidationError.invalidPackage
    }
  }

  private static func validateVersion(_ version: Int) throws {
    guard version > 0, version <= WhyboardBackupManifest.currentSchemaVersion else {
      throw BackupValidationError.unsupportedVersion
    }
  }

  private static func validateCounts(_ manifest: WhyboardBackupManifest) throws {
    let library = manifest.library
    let actual = BackupCounts(
      folders: library.folders.count,
      notes: library.notes.count,
      pages: library.pages.count,
      importedDocuments: library.importedDocuments.count,
      payloadFiles: manifest.payloads.count)
    guard actual == manifest.counts else { throw BackupValidationError.countMismatch }
  }

  private static func validateIdentifiers(_ library: BackupLibrary) throws {
    try requireUnique(library.folders.map(\.id))
    try requireUnique(library.notes.map(\.id))
    try requireUnique(library.pages.map(\.id))
    try requireUnique(library.importedDocuments.map(\.id))
  }

  private static func requireUnique(_ ids: [UUID]) throws {
    guard Set(ids).count == ids.count else {
      throw BackupValidationError.duplicateIdentifier
    }
  }

  private static func validateReferences(
    _ library: BackupLibrary,
    payloads: [BackupPayload]
  ) throws {
    let folderIDs = Set(library.folders.map(\.id))
    let notesByID = Dictionary(uniqueKeysWithValues: library.notes.map { ($0.id, $0) })
    let documentsByID = Dictionary(
      uniqueKeysWithValues: library.importedDocuments.map { ($0.id, $0) })
    guard library.notes.allSatisfy({ folderIDs.contains($0.folderID) }) else {
      throw BackupValidationError.invalidReference
    }
    guard library.pages.allSatisfy({ notesByID[$0.noteID] != nil }) else {
      throw BackupValidationError.invalidReference
    }
    guard library.importedDocuments.allSatisfy({ notesByID[$0.noteID] != nil }) else {
      throw BackupValidationError.invalidReference
    }
    try validatePageDocuments(library.pages, documentsByID: documentsByID)
    try validateReferencedPayloads(library, paths: Set(payloads.map(\.relativePath)))
  }

  private static func validatePageDocuments(
    _ pages: [BackupPageRecord],
    documentsByID: [UUID: BackupDocumentRecord]
  ) throws {
    for page in pages {
      guard let documentID = page.importedDocumentID else { continue }
      guard
        let document = documentsByID[documentID],
        document.noteID == page.noteID,
        let index = page.importedDocumentPageIndex,
        index >= 0,
        index < document.pageCount
      else { throw BackupValidationError.invalidReference }
    }
  }

  private static func validateReferencedPayloads(
    _ library: BackupLibrary,
    paths: Set<String>
  ) throws {
    for document in library.importedDocuments {
      let path =
        "documents/\(document.noteID.uuidString.lowercased())/"
        + "\(document.id.uuidString.lowercased()).pdf"
      guard paths.contains(path) else { throw BackupFileError.missingPayload }
    }
    for page in library.pages {
      for filename in attachmentFilenames(page) {
        let path =
          "attachments/\(page.noteID.uuidString.lowercased())/"
          + "\(page.id.uuidString.lowercased())/\(filename)"
        guard paths.contains(path) else { throw BackupFileError.missingPayload }
      }
    }
  }

  private static func attachmentFilenames(_ page: BackupPageRecord) -> Set<String> {
    Set(WorkspaceElementCoding.decode(page.workspaceElementsData).compactMap(\.assetFilename))
  }

  private static func validatePayloads(
    _ payloads: [BackupPayload],
    package: URL
  ) throws {
    guard Set(payloads.map(\.relativePath)).count == payloads.count else {
      throw BackupValidationError.duplicatePayload
    }
    for payload in payloads {
      try validatePayload(payload, package: package)
    }
  }

  private static func validatePayload(
    _ payload: BackupPayload,
    package: URL
  ) throws {
    guard BackupFileUtilities.isSafeRelativePath(payload.relativePath) else {
      throw BackupFileError.unsafePath
    }
    let url = package.appending(path: "Payload").appending(path: payload.relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw BackupFileError.missingPayload
    }
    guard try BackupFileUtilities.byteSize(of: url) == payload.byteSize else {
      throw BackupFileError.checksumMismatch
    }
    guard try BackupFileUtilities.sha256(of: url) == payload.sha256 else {
      throw BackupFileError.checksumMismatch
    }
  }
}
