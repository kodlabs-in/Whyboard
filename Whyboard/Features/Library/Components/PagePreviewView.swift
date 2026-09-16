import SwiftUI
import UIKit

struct PagePreviewView: View {
  let descriptor: PagePreviewDescriptor
  let drawingRepository: DrawingRepository
  let placeholderSystemImage: String
  let placeholderColor: Color

  @State private var image: UIImage?

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: placeholderSystemImage)
          .font(.title2.weight(.medium))
          .foregroundStyle(placeholderColor)
      }
    }
    .task(id: descriptor.taskID) {
      image = nil
      image = await drawingRepository.preview(for: descriptor)
    }
    .accessibilityHidden(true)
  }
}

struct PageThumbnailView: View {
  @AppStorage(NotePaperStyle.defaultStorageKey, store: AppPreferences.store)
  private var defaultPaperStyleRawValue = NotePaperStyle.defaultStyle.rawValue

  let note: Note
  let page: Page
  let pageNumber: Int
  let drawingRepository: DrawingRepository
  var isSelected = false

  private var paperStyle: NotePaperStyle {
    note.paperStyle.resolved(defaultRawValue: defaultPaperStyleRawValue)
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(WhyboardTheme.paperColor(for: paperStyle))

      PagePreviewView(
        descriptor: PagePreviewDescriptor(page: page, noteKind: note.kind),
        drawingRepository: drawingRepository,
        placeholderSystemImage: "doc.plaintext",
        placeholderColor: WhyboardTheme.pageControlColor(for: paperStyle)
      )
      .padding(5)

      Text("\(pageNumber)")
        .font(.caption2.bold().monospacedDigit())
        .foregroundStyle(WhyboardTheme.pageControlColor(for: paperStyle))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .padding(6)
    }
    .aspectRatio(WhyboardTheme.pageAspectRatio, contentMode: .fit)
    .overlay {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .stroke(
          isSelected ? WhyboardTheme.accent : WhyboardTheme.pageBorderColor(for: paperStyle),
          lineWidth: isSelected ? 3 : 1)
    }
    .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Page \(pageNumber) preview")
    .accessibilityValue(isSelected ? "Current page" : "")
  }
}
