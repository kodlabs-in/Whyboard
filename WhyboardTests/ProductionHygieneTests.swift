import Testing
import UIKit

@testable import Whyboard

@MainActor
struct ProductionHygieneTests {
  @Test func registeredSystemImagesAreAvailable() {
    #expect(UIImage(systemName: WhyboardSymbols.jumpToPage) != nil)
  }
}
