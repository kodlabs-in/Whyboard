import SwiftUI

struct FolderCard: View {
  let folder: Folder

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "folder.fill")
        .font(.system(size: 46, weight: .medium))
        .foregroundStyle(
          LinearGradient(
            colors: [WhyboardTheme.accent, WhyboardTheme.accent.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing))

      Text(folder.name)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(2)

      Label("Folder", systemImage: "arrow.right")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(WhyboardTheme.accent.opacity(0.12), lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Folder, \(folder.name)")
    .accessibilityHint("Opens this folder")
  }
}
