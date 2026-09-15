import Foundation

struct ConfirmationRequest: Identifiable {
  let id = UUID()
  let title: String
  let message: String
  let actionTitle: String
  let action: () -> Void
}
