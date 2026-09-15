import SwiftUI
import UIKit

enum WhyboardTheme {
  static let accent = Color(red: 0.26, green: 0.33, blue: 0.82)
  static let warmBackground = Color(
    uiColor: UIColor { traits in
      if traits.userInterfaceStyle == .dark {
        return UIColor(red: 0.055, green: 0.052, blue: 0.048, alpha: 1)
      }
      return UIColor(red: 0.965, green: 0.957, blue: 0.94, alpha: 1)
    })
  static let chromeBackground = Color(uiColor: .systemBackground)
  static let secondaryInk = Color.secondary.opacity(0.82)

  static let pageAspectRatio = CanonicalPage.size.width / CanonicalPage.size.height
  static let pageCornerRadius = 12.0

  static func paperColor(for style: NotePaperStyle) -> Color {
    switch style {
    case .automatic, .white:
      Color(red: 0.997, green: 0.995, blue: 0.985)
    case .cream:
      Color(red: 0.976, green: 0.941, blue: 0.843)
    case .black:
      Color(red: 0.055, green: 0.059, blue: 0.071)
    case .softBlue:
      Color(red: 0.91, green: 0.953, blue: 0.99)
    }
  }

  static func pageControlColor(for style: NotePaperStyle) -> Color {
    style.isDark ? Color.white.opacity(0.72) : Color.black.opacity(0.58)
  }

  static func pageBorderColor(for style: NotePaperStyle) -> Color {
    style.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
  }
}
