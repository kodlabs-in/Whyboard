import Foundation

/// The supported complexity budget for durable user-supplied content.
///
/// These limits are intentionally shared by direct imports, backup creation, and backup restore so
/// every path accepts the same document. They protect local availability; they are not quotas on
/// ordinary drawing data created inside Whyboard.
nonisolated enum ResourceLimits {
  static let maximumImageSourceBytes: Int64 = 50 * 1_024 * 1_024
  static let maximumImagePixels: Int64 = 100_000_000

  static let maximumPDFSourceBytes: Int64 = 512 * 1_024 * 1_024
  static let maximumPDFPages = 500
  static let maximumPDFPageDimension: Double = 20_000

  static let maximumManifestBytes: Int64 = 16 * 1_024 * 1_024
  /// Record and payload arrays share this budget before the encoded-byte cap is applied. At 16 MiB
  /// this leaves hundreds of bytes per entry while preventing attacker-controlled large allocations.
  static let maximumManifestEntries = 25_000
  static let maximumFolders = 5_000
  static let maximumNotes = 10_000
  static let maximumPages = 20_000
  static let maximumDocuments = 5_000
  static let maximumWorkspaceElementsPerPage = 10_000
  static let maximumWorkspaceElementsTotal = maximumManifestEntries

  static let maximumPayloadFiles = maximumManifestEntries
  /// Includes the manifest, payload files, and the narrow directory tree used by those payloads.
  /// Inventory is streamed and stopped at this value before an attacker can materialize a huge list.
  static let maximumPackageInventoryEntries = maximumManifestEntries * 5 + 16
  /// The generic ceiling must be at least the largest directly importable payload. Category-specific
  /// image and PDF ceilings are still enforced when their relative paths identify those resources.
  static let maximumPayloadBytes: Int64 = maximumPDFSourceBytes
  static let maximumTotalPayloadBytes: Int64 = 8 * 1_024 * 1_024 * 1_024

  static let maximumFolderDepth = 64
  static let maximumNameLength = 1_024
  static let maximumTextLength = 1_000_000
  static let maximumCoordinateMagnitude = 10_000_000.0
  static let maximumElementDimension = 1_000_000.0
  static let maximumSortOrder = 10_000_000
  static let maximumContentRevision: Int64 = 1_000_000_000
  static let maximumZIndex = 1_000_000

  /// Leaves room for both staging and final payloads plus normal filesystem overhead.
  static func restoreWorkingBytes(for payloadBytes: Int64, packageBytes: Int64) -> Int64? {
    let (doubledPayload, payloadOverflow) = payloadBytes.multipliedReportingOverflow(by: 2)
    let (required, totalOverflow) = doubledPayload.addingReportingOverflow(packageBytes)
    let (withOverhead, overheadOverflow) = required.addingReportingOverflow(10 * 1_024 * 1_024)
    guard !payloadOverflow, !totalOverflow, !overheadOverflow else { return nil }
    return withOverhead
  }

  /// Backup staging briefly needs the copied payload plus conservative filesystem/manifest headroom.
  static func backupWorkingBytes(for payloadBytes: Int64) -> Int64? {
    guard payloadBytes >= 0 else { return nil }
    let (required, overflow) = payloadBytes.addingReportingOverflow(10 * 1_024 * 1_024)
    guard !overflow else { return nil }
    return required
  }
}

nonisolated enum ImportFilePreflightError: Error {
  case invalidSource
  case resourceLimitExceeded
  case insufficientStorage
}

nonisolated enum ImportFilePreflight {
  static func inspectRegularFile(_ source: URL, maximumBytes: Int64) throws -> Int64 {
    let values = try source.resourceValues(
      forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard
      values.isRegularFile == true,
      values.isSymbolicLink != true,
      let size = values.fileSize,
      size > 0
    else { throw ImportFilePreflightError.invalidSource }
    let byteSize = Int64(size)
    guard byteSize <= maximumBytes else {
      throw ImportFilePreflightError.resourceLimitExceeded
    }
    return byteSize
  }

  static func requireCapacity(for byteSize: Int64, at destinationRoot: URL) throws {
    let (required, overflow) = byteSize.addingReportingOverflow(1 * 1_024 * 1_024)
    guard !overflow else { throw ImportFilePreflightError.resourceLimitExceeded }
    let values = try destinationRoot.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
    guard available >= required else { throw ImportFilePreflightError.insufficientStorage }
  }
}
