import SwiftUI

struct NoteRow: View {
  let note: Note
  let pageCount: Int

  var body: some View {
    HStack(spacing: 14) {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(WhyboardTheme.accent.opacity(0.12))
        .frame(width: 46, height: 58)
        .overlay {
          Image(systemName: "note.text")
            .font(.title3)
            .foregroundStyle(WhyboardTheme.accent)
        }

      VStack(alignment: .leading, spacing: 5) {
        Text(note.title)
          .font(.headline)
          .lineLimit(2)

        HStack(spacing: 6) {
          Text(pageCount == 1 ? "1 page" : "\(pageCount) pages")
          Text("•")
          Text(note.updatedAt, format: .relative(presentation: .named))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
  }
}
