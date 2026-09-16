import Foundation

nonisolated struct WhyboardBackupManifest: Codable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let appVersion: String
  let createdAt: Date
  let counts: BackupCounts
  let library: BackupLibrary
  let payloads: [BackupPayload]
}

nonisolated struct BackupCounts: Codable, Equatable, Sendable {
  let folders: Int
  let notes: Int
  let pages: Int
  let importedDocuments: Int
  let payloadFiles: Int
}

nonisolated struct BackupPayload: Codable, Equatable, Sendable {
  let relativePath: String
  let byteSize: Int64
  let sha256: String
}

nonisolated struct BackupLibrary: Codable, Sendable {
  let folders: [BackupFolderRecord]
  let notes: [BackupNoteRecord]
  let pages: [BackupPageRecord]
  let importedDocuments: [BackupDocumentRecord]

  @MainActor init(
    folders: [Folder],
    notes: [Note],
    pages: [Page],
    importedDocuments: [ImportedDocument]
  ) {
    self.folders = folders.map(BackupFolderRecord.init)
    self.notes = notes.map(BackupNoteRecord.init)
    self.pages = pages.map(BackupPageRecord.init)
    self.importedDocuments = importedDocuments.map(BackupDocumentRecord.init)
  }
}

nonisolated struct BackupFolderRecord: Codable, Sendable {
  let id: UUID
  let parentFolderID: UUID?
  let name: String
  let sortOrder: Int
  let createdAt: Date
  let updatedAt: Date
  let isSystem: Bool

  @MainActor init(_ folder: Folder) {
    id = folder.id
    parentFolderID = folder.parentFolderID
    name = folder.name
    sortOrder = folder.sortOrder
    createdAt = folder.createdAt
    updatedAt = folder.updatedAt
    isSystem = folder.isSystem
  }
}

nonisolated struct BackupNoteRecord: Codable, Sendable {
  let id: UUID
  let folderID: UUID
  let title: String
  let createdAt: Date
  let updatedAt: Date
  let lastOpenedAt: Date?
  let lastScrollOffset: Double
  let paperStyleRawValue: String?
  let noteKindRawValue: String?
  let canvasOffsetX: Double?
  let canvasOffsetY: Double?
  let canvasZoomScale: Double?
  let isFavorite: Bool?

  @MainActor init(_ note: Note) {
    id = note.id
    folderID = note.folderID
    title = note.title
    createdAt = note.createdAt
    updatedAt = note.updatedAt
    lastOpenedAt = note.lastOpenedAt
    lastScrollOffset = note.lastScrollOffset
    paperStyleRawValue = note.paperStyleRawValue
    noteKindRawValue = note.noteKindRawValue
    canvasOffsetX = note.canvasOffsetX
    canvasOffsetY = note.canvasOffsetY
    canvasZoomScale = note.canvasZoomScale
    isFavorite = note.isFavorite
  }
}

nonisolated struct BackupPageRecord: Codable, Sendable {
  let id: UUID
  let noteID: UUID
  let sortOrder: Int
  let contentRevision: Int64
  let createdAt: Date
  let updatedAt: Date
  let workspaceElementsData: Data?
  let importedDocumentID: UUID?
  let importedDocumentPageIndex: Int?

  @MainActor init(_ page: Page) {
    id = page.id
    noteID = page.noteID
    sortOrder = page.sortOrder
    contentRevision = page.contentRevision
    createdAt = page.createdAt
    updatedAt = page.updatedAt
    workspaceElementsData = page.workspaceElementsData
    importedDocumentID = page.importedDocumentID
    importedDocumentPageIndex = page.importedDocumentPageIndex
  }
}

nonisolated struct BackupDocumentRecord: Codable, Sendable {
  let id: UUID
  let noteID: UUID
  let filename: String
  let pageCount: Int
  let createdAt: Date
  let formatVersion: Int

  @MainActor init(_ document: ImportedDocument) {
    id = document.id
    noteID = document.noteID
    filename = document.filename
    pageCount = document.pageCount
    createdAt = document.createdAt
    formatVersion = document.formatVersion
  }
}

nonisolated struct BackupExportResult: Identifiable, Sendable {
  let id = UUID()
  let url: URL
  let counts: BackupCounts
}

nonisolated struct RestoreResult: Sendable {
  let folders: Int
  let notes: Int
  let pages: Int
}
