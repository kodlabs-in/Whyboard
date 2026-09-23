// swiftlint:disable file_length

import Foundation

enum BackupValidationError: LocalizedError {
  case invalidPackage
  case unsupportedVersion
  case countMismatch
  case duplicateIdentifier
  case duplicatePayload
  case invalidReference
  case invalidTopology
  case invalidValue
  case invalidWorkspaceData
  case resourceLimitExceeded
  case unexpectedFile

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
    case .invalidTopology:
      "The backup contains an invalid or excessively deep folder hierarchy."
    case .invalidValue:
      "The backup contains a value Whyboard cannot restore safely."
    case .invalidWorkspaceData:
      "The backup contains a malformed workspace object."
    case .resourceLimitExceeded:
      "This backup is too large or complex to restore safely."
    case .unexpectedFile:
      "The backup contains an unlisted or unsupported file."
    }
  }
}

// This validator intentionally keeps the complete trust boundary in one auditable namespace.
// swiftlint:disable type_body_length
nonisolated enum BackupValidator {
  private static let supportedEmptyPayloadDirectories: Set<String> = [
    "Payload",
    "Payload/drawings",
    "Payload/drawings/rawings",
    "Payload/attachments",
    "Payload/attachments/chments",
    "Payload/documents",
    "Payload/documents/cuments",
  ]

  static func referencedAttachmentPaths(in library: BackupLibrary) throws -> Set<String> {
    try validateResourceCounts(
      BackupCounts(
        folders: library.folders.count,
        notes: library.notes.count,
        pages: library.pages.count,
        importedDocuments: library.importedDocuments.count,
        payloadFiles: 0))
    return try validateSemanticValues(library)
  }

  static func validate(package: URL) throws -> WhyboardBackupManifest {
    try validatePackageRoot(package)
    let manifest = try decodeManifest(package: package)
    try validateVersion(manifest.schemaVersion)
    try validateCounts(manifest)
    try validateIdentifiers(manifest.library)
    let referencedAttachments = try validateSemanticValues(manifest.library)
    try validateTopology(manifest.library)
    try validateReferences(
      manifest.library,
      payloads: manifest.payloads,
      referencedAttachments: referencedAttachments)
    try validatePayloads(manifest.payloads, package: package)
    try validatePackageInventory(manifest.payloads, package: package)
    try validateRestoredImages(
      referencedAttachments,
      payloads: manifest.payloads,
      package: package)
    try validateRestoredPDFs(
      manifest.library.importedDocuments,
      payloads: manifest.payloads,
      package: package)
    return manifest
  }

  static func totalPayloadBytes(_ manifest: WhyboardBackupManifest) throws -> Int64 {
    try manifest.payloads.reduce(0) { total, payload in
      let (next, overflow) = total.addingReportingOverflow(payload.byteSize)
      guard !overflow else { throw BackupValidationError.resourceLimitExceeded }
      return next
    }
  }

  private static func validatePackageRoot(_ package: URL) throws {
    do {
      let values = try package.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw BackupValidationError.invalidPackage
      }
    } catch let error as BackupValidationError {
      throw error
    } catch {
      throw BackupValidationError.invalidPackage
    }
  }

  private static func decodeManifest(package: URL) throws -> WhyboardBackupManifest {
    let url = package.appending(path: "manifest.json")
    do {
      let values = try url.resourceValues(
        forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
      guard
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let byteSize = values.fileSize,
        byteSize > 0,
        Int64(byteSize) <= ResourceLimits.maximumManifestBytes
      else { throw BackupValidationError.resourceLimitExceeded }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
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
    try validateResourceCounts(actual)
  }

  static func validateResourceCounts(_ counts: BackupCounts) throws {
    guard
      counts.folders >= 0,
      counts.notes >= 0,
      counts.pages >= 0,
      counts.importedDocuments >= 0,
      counts.payloadFiles >= 0,
      counts.folders <= ResourceLimits.maximumFolders,
      counts.notes <= ResourceLimits.maximumNotes,
      counts.pages <= ResourceLimits.maximumPages,
      counts.importedDocuments <= ResourceLimits.maximumDocuments,
      counts.payloadFiles <= ResourceLimits.maximumPayloadFiles
    else { throw BackupValidationError.resourceLimitExceeded }
    var aggregate = 0
    for count in [
      counts.folders, counts.notes, counts.pages, counts.importedDocuments,
      counts.payloadFiles,
    ] {
      let (next, overflow) = aggregate.addingReportingOverflow(count)
      guard !overflow, next <= ResourceLimits.maximumManifestEntries else {
        throw BackupValidationError.resourceLimitExceeded
      }
      aggregate = next
    }
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

  // swiftlint:disable:next cyclomatic_complexity
  private static func validateSemanticValues(_ library: BackupLibrary) throws -> Set<String> {
    for folder in library.folders {
      try validateName(folder.name)
      try validateSortOrder(folder.sortOrder)
    }
    for note in library.notes {
      try validateName(note.title)
      guard
        note.lastScrollOffset.isFinite,
        abs(note.lastScrollOffset) <= ResourceLimits.maximumCoordinateMagnitude,
        note.canvasOffsetX.map(isValidCoordinate) ?? true,
        note.canvasOffsetY.map(isValidCoordinate) ?? true,
        note.canvasZoomScale.map({ $0.isFinite && $0 >= 0.05 && $0 <= 100 }) ?? true,
        note.paperStyleRawValue.map({ NotePaperStyle(rawValue: $0) != nil }) ?? true,
        note.noteKindRawValue.map({ NoteKind(rawValue: $0) != nil }) ?? true
      else { throw BackupValidationError.invalidValue }
    }
    var referencedAttachments = Set<String>()
    var totalElements = 0
    for page in library.pages {
      try validateSortOrder(page.sortOrder)
      guard
        page.contentRevision >= 0,
        page.contentRevision <= ResourceLimits.maximumContentRevision
      else { throw BackupValidationError.invalidValue }
      let elements = try strictWorkspaceElements(page.workspaceElementsData)
      totalElements += elements.count
      guard totalElements <= ResourceLimits.maximumWorkspaceElementsTotal else {
        throw BackupValidationError.resourceLimitExceeded
      }
      for element in elements {
        try validateElement(element)
        if let filename = element.assetFilename {
          guard isSafeFilename(filename) else { throw BackupValidationError.invalidReference }
          referencedAttachments.insert(
            "attachments/\(page.noteID.uuidString.lowercased())/"
              + "\(page.id.uuidString.lowercased())/\(filename)")
        }
      }
    }
    for document in library.importedDocuments {
      guard
        document.pageCount > 0,
        document.pageCount <= ResourceLimits.maximumPDFPages,
        document.formatVersion > 0,
        document.formatVersion <= ImportedDocument.currentFormatVersion,
        document.filename == "\(document.id.uuidString.lowercased()).pdf"
      else { throw BackupValidationError.invalidValue }
    }
    return referencedAttachments
  }

  private static func strictWorkspaceElements(_ data: Data?) throws -> [WorkspaceElement] {
    guard let data else { return [] }
    guard data.count <= ResourceLimits.maximumManifestBytes else {
      throw BackupValidationError.resourceLimitExceeded
    }
    do {
      let elements = try JSONDecoder().decode([WorkspaceElement].self, from: data)
      guard elements.count <= ResourceLimits.maximumWorkspaceElementsPerPage else {
        throw BackupValidationError.resourceLimitExceeded
      }
      guard Set(elements.map(\.id)).count == elements.count else {
        throw BackupValidationError.duplicateIdentifier
      }
      return elements
    } catch let error as BackupValidationError {
      throw error
    } catch {
      throw BackupValidationError.invalidWorkspaceData
    }
  }

  private static func validateElement(_ element: WorkspaceElement) throws {
    let frame = element.frame
    guard
      element.isValidForPersistence,
      isValidCoordinate(frame.centerX),
      isValidCoordinate(frame.centerY),
      frame.width <= ResourceLimits.maximumElementDimension,
      frame.height <= ResourceLimits.maximumElementDimension,
      abs(frame.rotationDegrees) <= 1_000_000,
      element.zIndex >= -ResourceLimits.maximumZIndex,
      element.zIndex <= ResourceLimits.maximumZIndex,
      element.text.map({ $0.count <= ResourceLimits.maximumTextLength }) ?? true,
      element.displayName.map({ $0.count <= ResourceLimits.maximumNameLength }) ?? true
    else { throw BackupValidationError.invalidValue }
    switch element.kind {
    case .text:
      guard element.text != nil, element.shapeKind == nil, element.assetFilename == nil else {
        throw BackupValidationError.invalidWorkspaceData
      }
    case .shape:
      guard element.shapeKind != nil, element.assetFilename == nil else {
        throw BackupValidationError.invalidWorkspaceData
      }
    case .image:
      guard
        let filename = element.assetFilename,
        isSafeFilename(filename),
        element.aspectRatio.map({
          $0.isFinite && $0 > 0 && $0 <= ResourceLimits.maximumElementDimension
        }) ?? true
      else { throw BackupValidationError.invalidWorkspaceData }
    }
  }

  private static func validateTopology(_ library: BackupLibrary) throws {
    let foldersByID = Dictionary(uniqueKeysWithValues: library.folders.map { ($0.id, $0) })
    let systemFolders = library.folders.filter(\.isSystem)
    guard systemFolders.count == 1, systemFolders[0].parentFolderID == nil else {
      throw BackupValidationError.invalidTopology
    }
    for folder in library.folders where !folder.isSystem {
      guard folder.parentFolderID.map({ foldersByID[$0] != nil }) ?? true else {
        throw BackupValidationError.invalidTopology
      }
      var visited = Set<UUID>()
      var current: BackupFolderRecord? = folder
      var depth = 0
      while let candidate = current {
        guard visited.insert(candidate.id).inserted else {
          throw BackupValidationError.invalidTopology
        }
        depth += 1
        guard depth <= ResourceLimits.maximumFolderDepth else {
          throw BackupValidationError.invalidTopology
        }
        current = candidate.parentFolderID.flatMap { foldersByID[$0] }
      }
    }
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  private static func validateReferences(
    _ library: BackupLibrary,
    payloads: [BackupPayload],
    referencedAttachments: Set<String>
  ) throws {
    let folderIDs = Set(library.folders.map(\.id))
    let notesByID = Dictionary(uniqueKeysWithValues: library.notes.map { ($0.id, $0) })
    let pagesByID = Dictionary(uniqueKeysWithValues: library.pages.map { ($0.id, $0) })
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
    let canonicalPaths = Set(
      payloads.map { BackupFileUtilities.canonicalPayloadRelativePath($0.relativePath) })
    for document in library.importedDocuments {
      let path =
        "documents/\(document.noteID.uuidString.lowercased())/"
        + "\(document.id.uuidString.lowercased()).pdf"
      guard canonicalPaths.contains(path) else { throw BackupFileError.missingPayload }
    }
    guard referencedAttachments.isSubset(of: canonicalPaths) else {
      throw BackupFileError.missingPayload
    }
    for path in canonicalPaths {
      let components = path.split(separator: "/").map(String.init)
      switch components.first {
      case "drawings":
        guard
          components.count == 3,
          let noteID = UUID(uuidString: components[1]),
          let pageID = UUID(
            uuidString: URL(fileURLWithPath: components[2]).deletingPathExtension()
              .lastPathComponent),
          components[2].hasSuffix(".drawing"),
          pagesByID[pageID]?.noteID == noteID
        else { throw BackupValidationError.invalidReference }
      case "attachments":
        guard referencedAttachments.contains(path) else {
          throw BackupValidationError.invalidReference
        }
      case "documents":
        guard
          components.count == 3,
          let noteID = UUID(uuidString: components[1]),
          let documentID = UUID(
            uuidString: URL(fileURLWithPath: components[2]).deletingPathExtension()
              .lastPathComponent),
          components[2].hasSuffix(".pdf"),
          documentsByID[documentID]?.noteID == noteID
        else { throw BackupValidationError.invalidReference }
      default:
        throw BackupValidationError.invalidReference
      }
    }
  }

  private static func validatePageDocuments(
    _ pages: [BackupPageRecord],
    documentsByID: [UUID: BackupDocumentRecord]
  ) throws {
    for page in pages {
      if page.importedDocumentID == nil || page.importedDocumentPageIndex == nil {
        guard page.importedDocumentID == nil, page.importedDocumentPageIndex == nil else {
          throw BackupValidationError.invalidReference
        }
        continue
      }
      guard
        let documentID = page.importedDocumentID,
        let document = documentsByID[documentID],
        document.noteID == page.noteID,
        let index = page.importedDocumentPageIndex,
        index >= 0,
        index < document.pageCount
      else { throw BackupValidationError.invalidReference }
    }
  }

  private static func validatePayloads(_ payloads: [BackupPayload], package: URL) throws {
    guard Set(payloads.map(\.relativePath)).count == payloads.count else {
      throw BackupValidationError.duplicatePayload
    }
    guard
      Set(payloads.map { BackupFileUtilities.canonicalPayloadRelativePath($0.relativePath) }).count
        == payloads.count
    else { throw BackupValidationError.duplicatePayload }
    let payloadRoot = package.appending(path: "Payload", directoryHint: .isDirectory)
    var totalBytes: Int64 = 0
    for payload in payloads {
      guard
        payload.byteSize >= 0,
        payload.byteSize <= BackupFileUtilities.maximumPayloadBytes(for: payload.relativePath),
        BackupFileUtilities.isSafeRelativePath(payload.relativePath)
      else { throw BackupValidationError.resourceLimitExceeded }
      let (nextTotal, overflow) = totalBytes.addingReportingOverflow(payload.byteSize)
      guard !overflow, nextTotal <= ResourceLimits.maximumTotalPayloadBytes else {
        throw BackupValidationError.resourceLimitExceeded
      }
      totalBytes = nextTotal
      let url = payloadRoot.appending(path: payload.relativePath)
      try requireContainedRegularFile(url, root: payloadRoot)
      guard try BackupFileUtilities.byteSize(of: url) == payload.byteSize else {
        throw BackupFileError.checksumMismatch
      }
      guard try BackupFileUtilities.sha256(of: url) == payload.sha256 else {
        throw BackupFileError.checksumMismatch
      }
    }
  }

  private static func validatePackageInventory(_ payloads: [BackupPayload], package: URL) throws {
    let expectedFiles = Set(["manifest.json"] + payloads.map { "Payload/\($0.relativePath)" })
    var expectedDirectories = Set<String>()
    for file in expectedFiles where file.hasPrefix("Payload/") {
      insertAncestorDirectories(of: file, into: &expectedDirectories)
    }
    for payload in payloads {
      let canonicalPath = BackupFileUtilities.canonicalPayloadRelativePath(payload.relativePath)
      guard canonicalPath != payload.relativePath else { continue }
      // Affected legacy packages could contain the empty canonical directory tree alongside
      // aliased payload paths. Permit only the canonical counterpart implied by a listed payload.
      insertAncestorDirectories(
        of: "Payload/\(canonicalPath)",
        into: &expectedDirectories)
    }
    try validateEnumeratedInventory(
      package,
      expectedFiles: expectedFiles,
      expectedDirectories: expectedDirectories)
  }

  private static func insertAncestorDirectories(
    of file: String,
    into directories: inout Set<String>
  ) {
    var components = file.split(separator: "/").map(String.init)
    components.removeLast()
    while !components.isEmpty {
      directories.insert(components.joined(separator: "/"))
      components.removeLast()
    }
  }

  private static func validateEnumeratedInventory(
    _ package: URL,
    expectedFiles: Set<String>,
    expectedDirectories: Set<String>
  ) throws {
    var enumerationError: Error?
    guard
      let enumerator = FileManager.default.enumerator(
        at: package,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
        options: [],
        errorHandler: { _, error in
          enumerationError = error
          return false
        })
    else { throw BackupValidationError.invalidPackage }
    var visitedEntries = 0
    while let child = enumerator.nextObject() as? URL {
      try Task.checkCancellation()
      visitedEntries += 1
      guard visitedEntries <= ResourceLimits.maximumPackageInventoryEntries else {
        throw BackupValidationError.resourceLimitExceeded
      }
      guard let relativePath = BackupFileUtilities.relativePath(of: child, under: package) else {
        throw BackupFileError.unsafePath
      }
      let values = try child.resourceValues(
        forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
      guard values.isSymbolicLink != true else { throw BackupValidationError.unexpectedFile }
      if values.isDirectory == true {
        guard
          relativePath.split(separator: "/").count <= ResourceLimits.maximumFolderDepth,
          expectedDirectories.contains(relativePath)
            || supportedEmptyPayloadDirectories.contains(relativePath)
        else {
          throw BackupValidationError.unexpectedFile
        }
      } else {
        guard values.isRegularFile == true, expectedFiles.contains(relativePath) else {
          throw BackupValidationError.unexpectedFile
        }
      }
    }
    guard enumerationError == nil else { throw BackupValidationError.invalidPackage }
  }

  private static func validateRestoredImages(
    _ referencedAttachments: Set<String>,
    payloads: [BackupPayload],
    package: URL
  ) throws {
    let paths = rawPayloadPathsByCanonicalPath(payloads)
    let payloadRoot = package.appending(path: "Payload", directoryHint: .isDirectory)
    for canonicalPath in referencedAttachments {
      try Task.checkCancellation()
      guard let rawPath = paths[canonicalPath] else { throw BackupFileError.missingPayload }
      _ = try ImageResourceValidator.validate(payloadRoot.appending(path: rawPath))
    }
  }

  private static func validateRestoredPDFs(
    _ documents: [BackupDocumentRecord],
    payloads: [BackupPayload],
    package: URL
  ) throws {
    let payloadRoot = package.appending(path: "Payload", directoryHint: .isDirectory)
    let paths = rawPayloadPathsByCanonicalPath(payloads)
    for document in documents {
      try Task.checkCancellation()
      let canonicalPath =
        "documents/\(document.noteID.uuidString.lowercased())/"
        + "\(document.id.uuidString.lowercased()).pdf"
      guard let rawPath = paths[canonicalPath] else { throw BackupFileError.missingPayload }
      let url = payloadRoot.appending(path: rawPath)
      _ = try PDFResourceValidator.validate(at: url, expectedPageCount: document.pageCount)
    }
  }

  private static func rawPayloadPathsByCanonicalPath(
    _ payloads: [BackupPayload]
  ) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: payloads.map {
        (BackupFileUtilities.canonicalPayloadRelativePath($0.relativePath), $0.relativePath)
      })
  }

  private static func requireContainedRegularFile(_ file: URL, root: URL) throws {
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw BackupFileError.missingPayload
    }
    let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
    let resolvedFile = file.resolvingSymlinksInPath().standardizedFileURL
    guard BackupFileUtilities.relativePath(of: resolvedFile, under: resolvedRoot) != nil else {
      throw BackupFileError.unsafePath
    }
    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw BackupValidationError.unexpectedFile
    }
  }

  private static func validateName(_ name: String) throws {
    guard !name.isEmpty, name.count <= ResourceLimits.maximumNameLength else {
      throw BackupValidationError.invalidValue
    }
  }

  private static func validateSortOrder(_ value: Int) throws {
    guard value >= 0, value <= ResourceLimits.maximumSortOrder else {
      throw BackupValidationError.invalidValue
    }
  }

  private static func isValidCoordinate(_ value: Double) -> Bool {
    value.isFinite && abs(value) <= ResourceLimits.maximumCoordinateMagnitude
  }

  private static func isSafeFilename(_ filename: String) -> Bool {
    !filename.isEmpty
      && filename.count <= ResourceLimits.maximumNameLength
      && filename != "."
      && filename != ".."
      && URL(fileURLWithPath: filename).lastPathComponent == filename
  }
}
// swiftlint:enable type_body_length file_length
