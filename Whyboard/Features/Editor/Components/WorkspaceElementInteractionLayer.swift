import SwiftUI

struct WorkspaceElementInteractionLayer: View {
  let session: ElementSession
  let transform: WorkspaceTransform
  let onFocus: () -> Void
  let onActivate: (WorkspaceElement) -> Void

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        ForEach(session.orderedElements) { element in
          if transform.isVisible(element, in: geometry.size) {
            WorkspaceElementInteractionView(
              element: element,
              isSelected: session.selectedElementID == element.id,
              transform: transform,
              session: session,
              onFocus: onFocus,
              onActivate: onActivate)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .clipped()
  }
}

private struct WorkspaceElementInteractionView: View {
  let element: WorkspaceElement
  let isSelected: Bool
  let transform: WorkspaceTransform
  let session: ElementSession
  let onFocus: () -> Void
  let onActivate: (WorkspaceElement) -> Void

  @State private var dragStart: WorkspaceElementFrame?
  @State private var resizeStart: WorkspaceElementFrame?
  @State private var rotationStart: WorkspaceElementFrame?
  @State private var isResizing = false

  private var screenFrame: CGRect {
    transform.screenFrame(for: element)
  }

  var body: some View {
    Color.clear
      .contentShape(
        WorkspaceElementHitShape(
          elementKind: element.kind,
          shapeKind: element.shapeKind)
      )
      .frame(width: screenFrame.width, height: screenFrame.height)
      .overlay { selectionBorder }
      .overlay(alignment: .bottomTrailing) { resizeHandle }
      .rotationEffect(.degrees(element.frame.rotationDegrees))
      .position(x: screenFrame.midX, y: screenFrame.midY)
      .zIndex(Double(element.zIndex) + 10_000)
      .onTapGesture {
        focusAndSelect()
      }
      .onTapGesture(count: 2) {
        focusAndSelect()
        onActivate(element)
      }
      .gesture(moveGesture)
      .simultaneousGesture(rotationGesture)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(element.accessibilityName)
      .accessibilityHint("Double tap to select and edit this object")
      .accessibilityIdentifier("workspace-element-\(element.kind.rawValue)")
  }

  @ViewBuilder
  private var selectionBorder: some View {
    if isSelected {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(WhyboardTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
    }
  }

  @ViewBuilder
  private var resizeHandle: some View {
    if isSelected {
      ZStack {
        Circle()
          .fill(WhyboardTheme.accent)
          .frame(width: 28, height: 28)
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .font(.caption2.bold())
          .foregroundStyle(.white)
      }
      .frame(width: 52, height: 52)
      .contentShape(Rectangle())
      .offset(x: 26, y: 26)
      .highPriorityGesture(resizeGesture)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Resize object")
      .accessibilityIdentifier("workspace-resize-handle")
    }
  }

  private var moveGesture: some Gesture {
    DragGesture(minimumDistance: 2)
      .onChanged { value in
        guard !isResizing else { return }
        let start = dragStart ?? element.frame
        dragStart = start
        focusAndSelect()
        session.previewFrame(
          start.translated(by: value.translation, scale: transform.scale),
          for: element.id)
      }
      .onEnded { value in
        guard !isResizing, let start = dragStart else { return }
        session.commitFrame(
          start.translated(by: value.translation, scale: transform.scale),
          for: element.id)
        dragStart = nil
      }
  }

  private var resizeGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        isResizing = true
        let start = resizeStart ?? element.frame
        resizeStart = start
        session.previewFrame(
          resizedFrame(from: start, translation: value.translation),
          for: element.id)
      }
      .onEnded { value in
        guard let start = resizeStart else { return }
        session.commitFrame(
          resizedFrame(from: start, translation: value.translation),
          for: element.id)
        resizeStart = nil
        isResizing = false
      }
  }

  private var rotationGesture: some Gesture {
    RotationGesture(minimumAngleDelta: .degrees(1))
      .onChanged { angle in
        guard isSelected, !isResizing else { return }
        let start = rotationStart ?? element.frame
        rotationStart = start
        session.previewFrame(start.rotated(by: angle.degrees), for: element.id)
      }
      .onEnded { angle in
        guard isSelected, let start = rotationStart else { return }
        session.commitFrame(start.rotated(by: angle.degrees), for: element.id)
        rotationStart = nil
      }
  }

  private func focusAndSelect() {
    onFocus()
    session.select(element.id)
  }

  private func resizedFrame(
    from frame: WorkspaceElementFrame,
    translation: CGSize
  ) -> WorkspaceElementFrame {
    if element.kind == .image || element.shapeKind?.preservesAspectRatio == true {
      return frame.resizedPreservingAspectRatio(by: translation, scale: transform.scale)
    }
    return frame.resized(by: translation, scale: transform.scale)
  }
}

nonisolated struct WorkspaceElementHitShape: Shape {
  let elementKind: WorkspaceElementKind
  let shapeKind: WorkspaceShapeKind?

  nonisolated func path(in rect: CGRect) -> Path {
    guard elementKind == .shape else { return Path(rect) }
    return WorkspaceShapePath.hitPath(for: shapeKind ?? .rectangle, in: rect)
  }
}
