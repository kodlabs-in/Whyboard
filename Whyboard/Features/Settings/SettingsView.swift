import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var folders: [Folder]
  @Query private var notes: [Note]
  @Query private var pages: [Page]
  @Query private var importedDocuments: [ImportedDocument]

  @AppStorage(NotePaperStyle.defaultStorageKey, store: AppPreferences.store)
  private var defaultPaperStyleRawValue = NotePaperStyle.defaultStyle.rawValue
  @AppStorage("drawWithFinger", store: AppPreferences.store) private var drawsWithFinger = false
  @State private var operation: DocumentOperationPresentation?
  @State private var operationTask: Task<Void, Never>?
  @State private var backupResult: BackupExportResult?
  @State private var isPickingBackup = false
  @State private var completionMessage: String?

  let drawingRepository: DrawingRepository

  var body: some View {
    Form {
      Section {
        Picker("Default Background", selection: $defaultPaperStyleRawValue) {
          ForEach(NotePaperStyle.selectableStyles) { style in
            paperStyleLabel(style)
              .tag(style.rawValue)
          }
        }
        .accessibilityIdentifier("default-paper-picker")
      } header: {
        Text("Background")
      } footer: {
        Text("New notes start with this colour. Existing notes keep their own background.")
      }

      Section("Writing") {
        Toggle("Draw with Finger", isOn: $drawsWithFinger)
      }

      Section("Keyboard Shortcuts") {
        shortcutRow("New Note", keys: "⌘N")
        shortcutRow("New Folder", keys: "⇧⌘N")
        shortcutRow("Find", keys: "⌘F")
        shortcutRow("Jump to Page", keys: "⌘G")
        shortcutRow("Duplicate", keys: "⌘D")
        shortcutRow("Export PDF", keys: "⌘P")
        shortcutRow("Previous / Next Page", keys: "⌥⌘← / ⌥⌘→")
        shortcutRow("Cancel", keys: "Esc")
      }

      Section {
        Button("Create Local Backup", systemImage: "externaldrive.badge.plus") {
          createBackup()
        }
        .disabled(operationTask != nil)
        .accessibilityIdentifier("create-backup")

        Button("Restore Backup", systemImage: "arrow.counterclockwise.icloud") {
          isPickingBackup = true
        }
        .disabled(operationTask != nil)
        .accessibilityIdentifier("restore-backup")
      } header: {
        Text("Backup & Restore")
      } footer: {
        Text("Backups are checksum-verified and stay local unless you choose to share them.")
      }

      Section("Privacy") {
        Label("Your notes stay on this iPad", systemImage: "lock.shield")
        Text("Whyboard works offline and does not send your drawings to a server.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $operation) { value in
      DocumentProgressSheet(operation: value, onCancel: cancelOperation)
    }
    .sheet(item: $backupResult, onDismiss: removeTemporaryBackup) { result in
      PDFShareSheet(url: result.url)
    }
    .fileImporter(
      isPresented: $isPickingBackup,
      allowedContentTypes: [.item],
      allowsMultipleSelection: false,
      onCompletion: handleBackupSelection
    )
    .alert("Backup & Restore", isPresented: completionIsPresented) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(completionMessage ?? "The operation finished.")
    }
  }

  private func paperStyleLabel(_ style: NotePaperStyle) -> some View {
    Label {
      Text(style.name)
    } icon: {
      Circle()
        .fill(WhyboardTheme.paperColor(for: style))
        .stroke(WhyboardTheme.pageBorderColor(for: style), lineWidth: 1)
        .frame(width: 22, height: 22)
    }
  }

  private func shortcutRow(_ name: String, keys: String) -> some View {
    HStack {
      Text(name)
      Spacer()
      Text(keys)
        .font(.body.monospaced())
        .foregroundStyle(.secondary)
        .accessibilityLabel(keys)
    }
  }

  private var completionIsPresented: Binding<Bool> {
    Binding(
      get: { completionMessage != nil },
      set: { if !$0 { completionMessage = nil } })
  }
}

private extension SettingsView {
  func createBackup() {
    guard operationTask == nil else { return }
    operation = DocumentOperationPresentation(title: "Creating Backup")
    operationTask = Task {
      do {
        let result = try await BackupService(drawingRepository: drawingRepository)
          .createBackup(
            folders: folders,
            notes: notes,
            pages: pages,
            importedDocuments: importedDocuments,
            onProgress: updateProgress)
        finishOperation(announcement: "Backup complete")
        backupResult = result
      } catch BackupCreationError.cancelled {
        finishOperation(announcement: "Backup cancelled")
      } catch {
        finishOperation(error: error)
      }
    }
  }

  func handleBackupSelection(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      restoreBackup(from: url)
    case .failure(let error):
      completionMessage = error.localizedDescription
    }
  }

  func restoreBackup(from url: URL) {
    guard operationTask == nil else { return }
    operation = DocumentOperationPresentation(title: "Validating & Restoring")
    operationTask = Task {
      do {
        let result = try await RestoreService(drawingRepository: drawingRepository)
          .restore(
            from: url,
            existingFolders: folders,
            context: modelContext,
            onProgress: updateProgress)
        finishOperation(announcement: "Restore complete")
        completionMessage =
          "Restored \(result.folders) folders, \(result.notes) notes, "
          + "and \(result.pages) pages as independent copies."
      } catch RestoreError.cancelled {
        finishOperation(announcement: "Restore cancelled")
      } catch {
        finishOperation(error: error)
      }
    }
  }

  func updateProgress(_ progress: Double) {
    guard var current = operation else { return }
    current.progress = min(max(progress, 0), 1)
    operation = current
  }

  func cancelOperation() {
    operationTask?.cancel()
  }

  func finishOperation(announcement: String) {
    operationTask = nil
    operation = nil
    UIAccessibility.post(notification: .announcement, argument: announcement)
  }

  func finishOperation(error: Error) {
    operationTask = nil
    operation = nil
    completionMessage = error.localizedDescription
  }

  func removeTemporaryBackup() {
    guard let url = backupResult?.url else { return }
    try? FileManager.default.removeItem(at: url)
  }
}
