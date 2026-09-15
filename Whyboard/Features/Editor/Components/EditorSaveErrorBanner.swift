import SwiftUI

struct EditorSaveErrorBanner: View {
  let status: EditorSaveStatus
  let onRetry: () -> Void

  @ViewBuilder
  var body: some View {
    if case .failed(let message) = status {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
        Text(message)
          .font(.callout)
        Spacer()
        Button("Retry", action: onRetry)
      }
      .foregroundStyle(.red)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.regularMaterial)
    }
  }
}
