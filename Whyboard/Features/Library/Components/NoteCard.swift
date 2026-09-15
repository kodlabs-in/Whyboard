import SwiftUI

struct NoteCard: View {
  @AppStorage(NotePaperStyle.defaultStorageKey, store: AppPreferences.store)
  private var defaultPaperStyleRawValue = NotePaperStyle.defaultStyle.rawValue

  let note: Note
  let pageCount: Int

  private var paperStyle: NotePaperStyle {
    note.paperStyle.resolved(defaultRawValue: defaultPaperStyleRawValue)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(WhyboardTheme.paperColor(for: paperStyle))
        .aspectRatio(1.5, contentMode: .fit)
        .overlay {
          Image(systemName: "pencil.line")
            .font(.title2.weight(.medium))
            .foregroundStyle(WhyboardTheme.pageControlColor(for: paperStyle))
        }
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(WhyboardTheme.pageBorderColor(for: paperStyle), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)

      Text(note.title)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(2)

      HStack(spacing: 6) {
        Text(pageCount == 1 ? "1 page" : "\(pageCount) pages")
        Text("•")
        Text(note.updatedAt, format: .relative(presentation: .named))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Note, \(note.title), \(pageCount) pages")
    .accessibilityHint("Opens this note")
  }
}
