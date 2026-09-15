import SwiftUI
import UIKit

struct PagePaperView: View {
  let page: Page
  let pageNumber: Int
  let pageCount: Int
  let isLive: Bool
  let paperStyle: NotePaperStyle
  let drawsWithFinger: Bool
  let session: PageSession
  let drawingRepository: DrawingRepository
  let toolPickerController: ToolPickerController
  let onFocus: () -> Void
  let onInsertBefore: () -> Void
  let onInsertAfter: () -> Void
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
    if isLive, session.isLoaded {
      CanonicalCanvasView(
        drawing: session.drawing,
        drawsWithFinger: drawsWithFinger,
        toolPickerController: toolPickerController,
        onDrawingChanged: session.drawingDidChange,
        onFocused: onFocus)
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
    } else if isLive {
      ProgressView("Loading page")
        .tint(WhyboardTheme.accent)
    } else if let preview {
      Image(uiImage: preview)
        .resizable()
        .scaledToFit()
        .accessibilityHidden(true)
    } else {
      Color.clear
    }
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
