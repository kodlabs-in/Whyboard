import UIKit

extension PagePreviewRenderer {
  nonisolated static func paperColor(_ style: NotePaperStyle) -> UIColor {
    switch style {
    case .automatic, .white:
      UIColor(red: 0.997, green: 0.995, blue: 0.985, alpha: 1)
    case .cream:
      UIColor(red: 0.976, green: 0.941, blue: 0.843, alpha: 1)
    case .black:
      UIColor(red: 0.055, green: 0.059, blue: 0.071, alpha: 1)
    case .softBlue:
      UIColor(red: 0.91, green: 0.953, blue: 0.99, alpha: 1)
    }
  }
}
