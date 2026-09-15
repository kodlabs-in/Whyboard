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
  static let paper = Color(red: 0.997, green: 0.995, blue: 0.985)
  static let pageBorder = Color.black.opacity(0.08)
  static let secondaryInk = Color.secondary.opacity(0.82)

  static let pageAspectRatio = CanonicalPage.size.width / CanonicalPage.size.height
  static let pageCornerRadius = 12.0
}
