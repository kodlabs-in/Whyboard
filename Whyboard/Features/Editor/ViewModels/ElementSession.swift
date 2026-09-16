import CoreGraphics
import Foundation
import Observation

@Observable
final class ElementSession {
  private(set) var elements: [WorkspaceElement]
  private(set) var selectedElementID: UUID?

  let page: Page

  private let note: Note
  private let canvasSize: CGSize
  private let saveMetadata: () throws -> Void
  private let onError: (String) -> Void

  init(
    page: Page,
    note: Note,
    canvasSize: CGSize,
    saveMetadata: @escaping () throws -> Void,
    onError: @escaping (String) -> Void
  ) {
    self.page = page
    self.note = note
    self.canvasSize = canvasSize
    self.saveMetadata = saveMetadata
    self.onError = onError
    elements = WorkspaceElementCoding.decode(page.workspaceElementsData)
  }

  var orderedElements: [WorkspaceElement] {
    elements.sorted { $0.zIndex < $1.zIndex }
  }

  var selectedElement: WorkspaceElement? {
    element(withID: selectedElementID)
  }

  @discardableResult
  func addText(at point: CGPoint) -> UUID {
    append(
      WorkspaceElement(
        kind: .text,
        frame: defaultFrame(centeredAt: point, size: CGSize(width: 300, height: 130)),
        zIndex: nextZIndex,
        text: "",
        color: .graphite))
  }

  @discardableResult
  func addShape(_ shape: WorkspaceShapeKind, at point: CGPoint) -> UUID {
    append(
      WorkspaceElement(
        kind: .shape,
        frame: defaultFrame(centeredAt: point, size: CGSize(width: 240, height: 180)),
        zIndex: nextZIndex,
        shapeKind: shape))
  }

  @discardableResult
  func addImage(_ image: ImportedImageAsset, at point: CGPoint) -> UUID {
    let size = WorkspaceElementFrame.aspectFittedSize(
      aspectRatio: image.aspectRatio,
      inside: CGSize(width: 360, height: 320))
    return append(
      WorkspaceElement(
        kind: .image,
        frame: defaultFrame(centeredAt: point, size: size),
        zIndex: nextZIndex,
        assetFilename: image.filename,
        displayName: image.displayName,
        aspectRatio: image.aspectRatio))
  }

  func select(_ elementID: UUID?) {
    selectedElementID = elementID
  }

  func previewFrame(_ frame: WorkspaceElementFrame, for elementID: UUID) {
    updateFrame(frame, for: elementID, savesChanges: false)
  }

  func commitFrame(_ frame: WorkspaceElementFrame, for elementID: UUID) {
    updateFrame(frame, for: elementID, savesChanges: true)
  }

  func updateSelectedText(_ text: String) {
    updateSelected { $0.text = text }
  }

  func updateSelectedColor(_ color: WorkspaceElementColor) {
    updateSelected { $0.color = color }
  }

  func updateImageAspectRatio(_ aspectRatio: Double, for elementID: UUID) {
    guard aspectRatio.isFinite, aspectRatio > 0 else { return }
    guard let index = elements.firstIndex(where: { $0.id == elementID }) else { return }
    guard elements[index].kind == .image else { return }
    guard abs((elements[index].aspectRatio ?? 0) - aspectRatio) > 0.001 else { return }

    let size = WorkspaceElementFrame.aspectFittedSize(
      aspectRatio: aspectRatio,
      inside: CGSize(width: 360, height: 320))
    elements[index].aspectRatio = aspectRatio
    elements[index].frame.width = size.width
    elements[index].frame.height = size.height
    elements[index].frame = elements[index].frame.clamped(to: canvasSize)
    persist()
  }

  func duplicateSelected() {
    guard var copy = selectedElement else { return }
    copy = WorkspaceElement(
      kind: copy.kind,
      frame: copy.frame
        .translated(by: CGSize(width: 28, height: 28), scale: 1)
        .clamped(to: canvasSize),
      zIndex: nextZIndex,
      text: copy.text,
      shapeKind: copy.shapeKind,
      color: copy.color,
      assetFilename: copy.assetFilename,
      displayName: copy.displayName,
      aspectRatio: copy.aspectRatio)
    append(copy)
  }

  func bringSelectedToFront() {
    let highestZIndex = nextZIndex
    updateSelected { $0.zIndex = highestZIndex }
  }

  func sendSelectedToBack() {
    let lowestZIndex = elements.map(\.zIndex).min() ?? 0
    updateSelected { $0.zIndex = lowestZIndex - 1 }
  }

  func deleteSelected() -> String? {
    guard let selectedElement else { return nil }
    elements.removeAll { $0.id == selectedElement.id }
    selectedElementID = nil
    persist()

    guard let filename = selectedElement.assetFilename else { return nil }
    let isStillReferenced = elements.contains { $0.assetFilename == filename }
    return isStillReferenced ? nil : filename
  }

  func element(withID id: UUID?) -> WorkspaceElement? {
    guard let id else { return nil }
    return elements.first { $0.id == id }
  }

  func retrySave() {
    persist()
  }

  private var nextZIndex: Int {
    (elements.map(\.zIndex).max() ?? -1) + 1
  }

  @discardableResult
  private func append(_ element: WorkspaceElement) -> UUID {
    elements.append(element)
    selectedElementID = element.id
    persist()
    return element.id
  }

  private func updateFrame(
    _ frame: WorkspaceElementFrame,
    for elementID: UUID,
    savesChanges: Bool
  ) {
    guard let index = elements.firstIndex(where: { $0.id == elementID }) else { return }
    elements[index].frame = frame.clamped(to: canvasSize)
    if savesChanges {
      persist()
    }
  }

  private func updateSelected(_ update: (inout WorkspaceElement) -> Void) {
    guard let index = elements.firstIndex(where: { $0.id == selectedElementID }) else { return }
    update(&elements[index])
    persist()
  }

  private func defaultFrame(centeredAt point: CGPoint, size: CGSize) -> WorkspaceElementFrame {
    WorkspaceElementFrame(center: point, size: size).clamped(to: canvasSize)
  }

  private func persist() {
    let previousData = page.workspaceElementsData
    let previousPageUpdate = page.updatedAt
    let previousNoteUpdate = note.updatedAt

    do {
      page.workspaceElementsData = try WorkspaceElementCoding.encode(elements)
      let now = Date()
      page.updatedAt = now
      note.updatedAt = now
      try saveMetadata()
    } catch {
      page.workspaceElementsData = previousData
      page.updatedAt = previousPageUpdate
      note.updatedAt = previousNoteUpdate
      onError(error.localizedDescription)
    }
  }
}
