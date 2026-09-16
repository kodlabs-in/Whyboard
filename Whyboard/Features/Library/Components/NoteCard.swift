import SwiftUI

struct NoteCard: View {
  @AppStorage(NotePaperStyle.defaultStorageKey, store: AppPreferences.store)
  private var defaultPaperStyleRawValue = NotePaperStyle.defaultStyle.rawValue

  let note: Note
  let pageCount: Int
  let previewPage: Page?
  let drawingRepository: DrawingRepository
  var isSelecting = false
  var isSelected = false
  let onOpen: () -> Void
  let onToggleFavorite: () -> Void

  private var paperStyle: NotePaperStyle {
    note.paperStyle.resolved(defaultRawValue: defaultPaperStyleRawValue)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Button(action: onOpen) {
        previewContent
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        "Open \(note.kind.name) note, \(note.title), "
          + note.kind.libraryDetail(pageCount: pageCount)
      )
      .accessibilityHint(accessibilityHint)
      .accessibilityValue(isSelecting ? (isSelected ? "Selected" : "Not selected") : "")
      .accessibilityAddTraits(isSelected ? .isSelected : [])

      HStack(alignment: .top, spacing: 10) {
        noteDetails
          .contentShape(Rectangle())
          .onTapGesture(perform: onOpen)

        Spacer(minLength: 4)
        selectionControl
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      if isSelecting, isSelected {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .stroke(WhyboardTheme.accent, lineWidth: 3)
      }
    }
  }

  private var accessibilityHint: String {
    guard isSelecting else { return "Opens this note" }
    return isSelected ? "Double tap to deselect" : "Double tap to select"
  }

  private var previewContent: some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(WhyboardTheme.paperColor(for: paperStyle))
      .aspectRatio(1.5, contentMode: .fit)
      .overlay {
        if let previewPage {
          PagePreviewView(
            descriptor: PagePreviewDescriptor(
              page: previewPage,
              note: note,
              paperStyle: paperStyle),
            drawingRepository: drawingRepository,
            placeholderSystemImage: note.kind.systemImage,
            placeholderColor: WhyboardTheme.pageControlColor(for: paperStyle)
          )
          .padding(6)
        } else {
          Image(systemName: note.kind.systemImage)
            .font(.title2.weight(.medium))
            .foregroundStyle(WhyboardTheme.pageControlColor(for: paperStyle))
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(WhyboardTheme.pageBorderColor(for: paperStyle), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
  }

  private var noteDetails: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(note.title)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(2)

      HStack(spacing: 6) {
        Text(note.kind.libraryDetail(pageCount: pageCount))
        Text("•")
        Text(note.updatedAt, format: .relative(presentation: .named))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
  }

  @ViewBuilder
  private var selectionControl: some View {
    if isSelecting {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.title2)
        .foregroundStyle(isSelected ? WhyboardTheme.accent : .secondary)
        .background(.background, in: Circle())
        .accessibilityHidden(true)
    } else {
      Button(action: onToggleFavorite) {
        Image(systemName: note.isFavorite == true ? "star.fill" : "star")
          .font(.body.weight(.semibold))
          .foregroundStyle(note.isFavorite == true ? .yellow : .secondary)
          .frame(width: 34, height: 34)
          .background(.regularMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(note.isFavorite == true ? "Remove from Favorites" : "Add to Favorites")
    }
  }
}
