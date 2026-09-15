import SwiftUI

struct EditorSaveStatusView: View {
  let status: EditorSaveStatus

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.caption.weight(.medium))
      .foregroundStyle(color)
      .labelStyle(.iconOnly)
      .accessibilityLabel(accessibilityLabel)
  }

  private var title: String {
    switch status {
    case .saved:
      "Saved"
    case .unsaved:
      "Unsaved"
    case .saving:
      "Saving"
    case .failed:
      "Save failed"
    }
  }

  private var systemImage: String {
    switch status {
    case .saved:
      "checkmark.circle.fill"
    case .unsaved:
      "circle.dotted"
    case .saving:
      "arrow.trianglehead.2.clockwise.rotate.90"
    case .failed:
      "exclamationmark.triangle.fill"
    }
  }

  private var color: Color {
    switch status {
    case .saved:
      .secondary
    case .unsaved, .saving:
      WhyboardTheme.accent
    case .failed:
      .red
    }
  }

  private var accessibilityLabel: String {
    switch status {
    case .failed(let message):
      "Save failed. \(message)"
    default:
      title
    }
  }
}
