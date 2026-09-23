import CoreGraphics
import Foundation
import Observation

struct ElementEditingTarget {
  let pageID: UUID
  let session: ElementSession
  let insertionPoint: CGPoint
}

@MainActor
@Observable
final class WorkspaceElementEditingController {
  var interactionMode = WorkspaceInteractionMode.draw
  var textEditorRequest: TextElementEditorRequest?
  var mediaPreviewRequest: MediaPreviewRequest?

  let mediaImportController: MediaImportController

  @ObservationIgnored private let noteID: UUID
  @ObservationIgnored private let attachments: AttachmentRepository
  @ObservationIgnored private var resolveTarget: ((UUID?) -> ElementEditingTarget?)?

  init(noteID: UUID, attachments: AttachmentRepository) {
    self.noteID = noteID
    self.attachments = attachments
    mediaImportController = MediaImportController(attachments: attachments)
  }

  var selectedElement: WorkspaceElement? {
    activeTarget?.session.selectedElement
  }

  func configure(
    resolveTarget: @escaping (UUID?) -> ElementEditingTarget?,
    onError: @escaping (String) -> Void
  ) {
    self.resolveTarget = resolveTarget
    mediaImportController.configure(
      noteID: noteID,
      onImported: { [weak self] pageID, image in
        self?.insert(image, on: pageID) == true
      },
      onError: onError)
  }

  func toggleInteractionMode() {
    interactionMode.toggle()
    if interactionMode == .draw {
      activeTarget?.session.select(nil)
    }
  }

  func addText() {
    guard let target = activeTarget else { return }
    interactionMode = .arrange
    target.session.addText(at: target.insertionPoint)
    editSelectedText()
  }

  func addShape(_ shape: WorkspaceShapeKind) {
    guard let target = activeTarget else { return }
    interactionMode = .arrange
    target.session.addShape(shape, at: target.insertionPoint)
  }

  func presentPhotoPicker() {
    guard let target = activeTarget else { return }
    mediaImportController.presentPhotoPicker(for: target.pageID)
  }

  func presentFileImporter() {
    guard let target = activeTarget else { return }
    mediaImportController.presentFileImporter(for: target.pageID)
  }

  func activate(_ element: WorkspaceElement, in session: ElementSession) {
    session.select(element.id)
    if element.kind == .text {
      editSelectedText()
    } else if element.kind == .image {
      previewSelectedMedia()
    }
  }

  func editSelectedText() {
    guard let target = activeTarget, let element = target.session.selectedElement else { return }
    textEditorRequest = TextElementEditorRequest(
      id: element.id,
      initialText: element.text ?? ""
    ) { [weak session = target.session] text in
      session?.updateSelectedText(text)
    }
  }

  func previewSelectedMedia() {
    guard
      let target = activeTarget,
      let element = target.session.selectedElement,
      let filename = element.assetFilename
    else { return }

    mediaPreviewRequest = MediaPreviewRequest(
      url: attachments.fileURL(
        noteID: noteID,
        pageID: target.pageID,
        filename: filename),
      title: element.displayName ?? "Attachment")
  }

  func setSelectedColor(_ color: WorkspaceElementColor) {
    activeTarget?.session.updateSelectedColor(color)
  }

  func duplicateSelected() {
    activeTarget?.session.duplicateSelected()
  }

  func bringSelectedToFront() {
    activeTarget?.session.bringSelectedToFront()
  }

  func sendSelectedToBack() {
    activeTarget?.session.sendSelectedToBack()
  }

  func deleteSelected() {
    guard let target = activeTarget else { return }
    _ = target.session.deleteSelected()
  }

  private var activeTarget: ElementEditingTarget? {
    resolveTarget?(nil)
  }

  private func insert(_ image: ImportedImageAsset, on pageID: UUID) -> Bool {
    guard let target = resolveTarget?(pageID) else { return false }
    interactionMode = .arrange
    return target.session.addImage(image, at: target.insertionPoint)
  }
}
