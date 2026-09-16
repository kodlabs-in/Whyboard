import SwiftUI

struct FolderCard: View {
  let folder: Folder
  var isSelecting = false
  var isSelected = false

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
        .stroke(
          isSelected ? WhyboardTheme.accent : WhyboardTheme.accent.opacity(0.12),
          lineWidth: isSelected ? 3 : 1)
    }
    .overlay(alignment: .topTrailing) {
      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .font(.title2)
          .foregroundStyle(WhyboardTheme.accent)
          .background(.background, in: Circle())
          .padding(12)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Folder, \(folder.name)")
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .accessibilityHint(accessibilityHint)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var accessibilityHint: String {
    guard isSelecting else { return "Opens this folder" }
    return isSelected ? "Double tap to deselect" : "Double tap to select"
  }
}
