import Foundation
import SwiftData
import Testing

@testable import Whyboard

private actor RestoreCopyGate {
  private var reached = false
  private var reachedWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func suspendAfterFirstCopy(_ count: Int) async {
    guard count == 1 else { return }
    reached = true
    let waiters = reachedWaiters
    reachedWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { releaseWaiter = $0 }
  }

  func waitUntilReached() async {
    if reached { return }
    await withCheckedContinuation { reachedWaiters.append($0) }
  }

  func release() {
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}

@MainActor
struct RestoreCancellationIntegrationTests {
  @Test func cancellationAfterPartialPayloadCopyCleansStagingAndPublishedPayloads() async throws {
    let source = try await BackupRestoreTests().makeFixture()
    let fresh = try BackupRestoreTests().makeFreshInstallation()
    defer {
      try? FileManager.default.removeItem(at: source.directories.root)
      try? FileManager.default.removeItem(at: fresh.directories.root)
    }
    let backup = try await BackupService(drawingRepository: source.repository)
      .createBackup(
        folders: source.folders,
        notes: [source.note],
        pages: [source.page],
        importedDocuments: [])
    let gate = RestoreCopyGate()
    let operation = Task {
      try await RestoreService(
        drawingRepository: fresh.repository,
        afterPayloadCopy: { count in await gate.suspendAfterFirstCopy(count) }
      ).restore(
        from: backup.url,
        existingFolders: [fresh.rootFolder],
        context: fresh.context)
    }

    await gate.waitUntilReached()
    operation.cancel()
    await gate.release()

    await #expect(throws: RestoreError.self) { try await operation.value }
    #expect(try fresh.context.fetchCount(FetchDescriptor<Note>()) == 0)
    #expect(try fresh.context.fetchCount(FetchDescriptor<Page>()) == 0)
    #expect(try regularFileCount(beneath: fresh.repository.drawingsDirectory) == 0)
    #expect(try regularFileCount(beneath: fresh.repository.attachments.rootDirectory) == 0)
    let staging = try FileManager.default.contentsOfDirectory(
      at: fresh.directories.backups,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix(".restore-") }
    #expect(staging.isEmpty)
  }

  private func regularFileCount(beneath root: URL) throws -> Int {
    guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
    let keys: [URLResourceKey] = [.isRegularFileKey]
    let enumerator = try #require(
      FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles]))
    var count = 0
    for case let url as URL in enumerator
    where try url.resourceValues(forKeys: Set(keys)).isRegularFile == true {
      count += 1
    }
    return count
  }
}
