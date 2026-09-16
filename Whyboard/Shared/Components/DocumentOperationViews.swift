import SwiftUI
import UIKit

struct DocumentOperationPresentation: Identifiable, Equatable {
  let id: UUID
  let title: String
  var progress: Double

  init(id: UUID = UUID(), title: String, progress: Double = 0) {
    self.id = id
    self.title = title
    self.progress = progress
  }
}

struct DocumentProgressSheet: View {
  let operation: DocumentOperationPresentation
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 22) {
      Image(systemName: "doc.badge.gearshape")
        .font(.system(size: 42, weight: .medium))
        .foregroundStyle(WhyboardTheme.accent)

      Text(operation.title)
        .font(.title2.bold())

      ProgressView(value: operation.progress) {
        Text("\(Int(operation.progress * 100)) percent")
          .font(.subheadline.monospacedDigit())
      }
      .accessibilityLabel(operation.title)
      .accessibilityValue("\(Int(operation.progress * 100)) percent")
      .accessibilityIdentifier("document-operation-progress")

      Button("Cancel", role: .cancel, action: onCancel)
        .buttonStyle(.bordered)
        .keyboardShortcut(.cancelAction)
    }
    .padding(32)
    .presentationDetents([.medium])
    .interactiveDismissDisabled()
  }
}

struct PDFShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
