import Testing
import UniformTypeIdentifiers
import UIKit

@testable import Whyboard

@MainActor
struct ProductionHygieneTests {
  @Test func registeredSystemImagesAreAvailable() {
    #expect(UIImage(systemName: WhyboardSymbols.jumpToPage) != nil)
  }

  @Test func backupPackageTypeIsDeclaredToTheSystem() throws {
    let declarations = try #require(
      Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations")
        as? [[String: Any]])
    let backupType = try #require(
      declarations.first { declaration in
        declaration["UTTypeIdentifier"] as? String == "in.kodlabs.whyboard.backup"
      })
    let conformances = try #require(backupType["UTTypeConformsTo"] as? [String])
    let tags = try #require(backupType["UTTypeTagSpecification"] as? [String: Any])
    let extensions = try #require(tags["public.filename-extension"] as? [String])

    #expect(conformances.contains("com.apple.package"))
    #expect(conformances.contains("public.content"))
    #expect(extensions.contains("whyboardbackup"))
    #expect(UTType.whyboardBackup.conforms(to: .package))
  }
}
