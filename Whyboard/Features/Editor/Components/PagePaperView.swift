import SwiftUI
import UIKit

struct PagePaperView: View {
  let page: Page
  let pageNumber: Int
  let pageCount: Int
  let isLive: Bool
  let paperStyle: NotePaperStyle
  let drawsWithFinger: Bool
  let interactionMode: WorkspaceInteractionMode
  let session: PageSession
  let elementSession: ElementSession
  let drawingRepository: DrawingRepository
  let toolPickerController: ToolPickerController
  let onFocus: () -> Void
  let onElementActivate: (WorkspaceElement) -> Void
  let onInsertBefore: () -> Void
  let onInsertAfter: () -> Void
  let onDuplicate: () -> Void
  let onDelete: () -> Void

  @State private var preview: UIImage?

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: WhyboardTheme.pageCornerRadius, style: .continuous)
        .fill(WhyboardTheme.paperColor(for: paperStyle))

      pageContent

      VStack {
        pageHeader
        Spacer()
      }
      .padding(12)
    }
    .clipShape(RoundedRectangle(cornerRadius: WhyboardTheme.pageCornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: WhyboardTheme.pageCornerRadius, style: .continuous)
        .stroke(WhyboardTheme.pageBorderColor(for: paperStyle), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    .aspectRatio(WhyboardTheme.pageAspectRatio, contentMode: .fit)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Page \(pageNumber)")
    .task(id: previewTaskID) {
      if isLive {
        preview = nil
        await session.loadIfNeeded()
      } else {
        preview = await drawingRepository.previews.preview(
          pageID: page.id,
          noteID: page.noteID,
          revision: page.contentRevision)
      }
    }
  }

  private var previewTaskID: String {
    "\(isLive)-\(page.contentRevision)"
  }

  @ViewBuilder
  private var pageContent: some View {
    if isLive {
      livePageContent
    } else {
      dormantPageContent
    }
  }

  @ViewBuilder
  private var livePageContent: some View {
    if session.isLoaded {
      canonicalWorkspace
    } else if case .failed(let message) = session.state {
      ContentUnavailableView {
        Label("Page unavailable", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try Again") {
          Task { await session.loadIfNeeded() }
        }
      }
    } else {
      ProgressView("Loading page")
        .tint(WhyboardTheme.accent)
    }
  }

  private var canonicalWorkspace: some View {
    GeometryReader { geometry in
      let transform = WorkspaceTransform(
        scale: geometry.size.width / CanonicalPage.size.width,
        contentOffset: .zero)

      ZStack {
        importedPDFBackground

        if interactionMode == .arrange {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              onFocus()
              elementSession.select(nil)
            }
        }

        elementVisualLayer(transform: transform)

        CanonicalCanvasView(
          drawing: session.drawing,
          drawsWithFinger: drawsWithFinger,
          toolPickerController: toolPickerController,
          onDrawingChanged: session.drawingDidChange,
          onFocused: onFocus
        )
        .allowsHitTesting(interactionMode == .draw)

        if interactionMode == .arrange {
          WorkspaceElementInteractionLayer(
            session: elementSession,
            transform: transform,
            onFocus: onFocus,
            onActivate: onElementActivate)
        }
      }
    }
  }

  @ViewBuilder
  private var importedPDFBackground: some View {
    if let background = importedBackgroundReference {
      ImportedPDFPageView(
        noteID: page.noteID,
        documentID: background.documentID,
        pageIndex: background.pageIndex,
        documents: drawingRepository.documents
      )
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  private var importedBackgroundReference: ImportedPDFBackground? {
    ImportedPDFBackground(page: page)
  }

  private var dormantPageContent: some View {
    GeometryReader { geometry in
      let transform = WorkspaceTransform(
        scale: geometry.size.width / CanonicalPage.size.width,
        contentOffset: .zero)

      ZStack {
        if let preview {
          Image(uiImage: preview)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
        } else {
          importedPDFBackground
          elementVisualLayer(transform: transform)
        }
      }
    }
  }

  private func elementVisualLayer(transform: WorkspaceTransform) -> some View {
    WorkspaceElementVisualLayer(
      elements: elementSession.orderedElements,
      noteID: page.noteID,
      pageID: page.id,
      attachments: drawingRepository.attachments,
      transform: transform,
      onImageAspectRatio: { elementID, aspectRatio in
        elementSession.updateImageAspectRatio(aspectRatio, for: elementID)
      })
  }

  private var pageHeader: some View {
    HStack(alignment: .top) {
      Text("PAGE \(pageNumber)")
        .font(.caption2.weight(.semibold))
        .tracking(0.8)
        .foregroundStyle(WhyboardTheme.pageControlColor(for: paperStyle))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())

      Spacer()

      Menu {
        Button("Insert Before", systemImage: "arrow.up.doc") { onInsertBefore() }
        Button("Insert After", systemImage: "arrow.down.doc") { onInsertAfter() }
        Button("Duplicate Page", systemImage: "plus.square.on.square", action: onDuplicate)
        Divider()
        Button("Delete Page", systemImage: "trash", role: .destructive) { onDelete() }
          .disabled(pageCount == 1)
      } label: {
        Image(systemName: "ellipsis")
          .font(.body.weight(.semibold))
          .foregroundStyle(WhyboardTheme.pageControlColor(for: paperStyle))
          .frame(width: 34, height: 30)
          .background(.thinMaterial, in: Capsule())
      }
      .accessibilityLabel("Page \(pageNumber) actions")
    }
  }
}
