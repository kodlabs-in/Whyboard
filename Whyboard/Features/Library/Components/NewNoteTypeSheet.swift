import SwiftUI

struct NewNoteTypeSheet: View {
  @Environment(\.dismiss) private var dismiss

  let onSelect: (NoteKind) -> Void

  private let columns = [
    GridItem(.adaptive(minimum: 210), spacing: 16)
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Text("How do you want to think?")
              .font(.title2.bold())
            Text("Choose a format for this note. You can create both kinds in any folder.")
              .foregroundStyle(.secondary)
          }

          LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(NoteKind.allCases) { kind in
              noteTypeButton(kind)
            }
          }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .background(WhyboardTheme.warmBackground)
      .navigationTitle("New Note")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: dismiss.callAsFunction)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationCornerRadius(28)
  }

  private func noteTypeButton(_ kind: NoteKind) -> some View {
    Button {
      dismiss()
      onSelect(kind)
    } label: {
      VStack(alignment: .leading, spacing: 14) {
        Image(systemName: kind.systemImage)
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(WhyboardTheme.accent)
          .frame(width: 58, height: 58)
          .background(WhyboardTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

        Text(kind.name)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(kind.description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)

        Spacer(minLength: 0)

        Label("Create", systemImage: "arrow.right.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(WhyboardTheme.accent)
      }
      .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
      .padding(18)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(WhyboardTheme.accent.opacity(0.16), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("new-note-type-\(kind.rawValue)")
    .accessibilityHint(kind.description)
  }
}
