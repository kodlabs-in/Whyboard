import Foundation
import Observation

@Observable
final class EditorUndoHistory {
  private struct Command {
    let scope: UUID
    let estimatedByteCost: Int
    let referencedAttachmentFilenames: Set<String>
    let undo: () async -> Bool
    let redo: () async -> Bool
  }

  private(set) var canUndo = false
  private(set) var canRedo = false

  @ObservationIgnored private let limit: Int
  @ObservationIgnored private let byteLimit: Int
  @ObservationIgnored private var undoStack: [Command] = []
  @ObservationIgnored private var redoStack: [Command] = []
  @ObservationIgnored private var isApplyingHistory = false
  @ObservationIgnored private var onDiscardedScopes: ((Set<UUID>) -> Void)?

  init(limit: Int = 100, byteLimit: Int = 32 * 1_024 * 1_024) {
    self.limit = max(1, limit)
    self.byteLimit = max(0, byteLimit)
  }

  func record(
    scope: UUID,
    estimatedByteCost: Int = 0,
    referencedAttachmentFilenames: Set<String> = [],
    undo: @escaping () async -> Bool,
    redo: @escaping () async -> Bool
  ) {
    guard !isApplyingHistory else { return }
    let discardedRedoScopes = Set(redoStack.map(\.scope))
    redoStack.removeAll()
    undoStack.append(
      Command(
        scope: scope,
        estimatedByteCost: max(0, estimatedByteCost),
        referencedAttachmentFilenames: referencedAttachmentFilenames,
        undo: undo,
        redo: redo))
    let evictedScopes = trimUndoStackToBudget()
    refreshState()
    notifyDiscardedScopes(discardedRedoScopes.union(evictedScopes))
  }

  @discardableResult
  func undo() async -> Bool {
    guard !isApplyingHistory, let command = undoStack.last else { return false }
    isApplyingHistory = true
    let didCommit = await command.undo()
    isApplyingHistory = false
    guard didCommit else {
      refreshState()
      return false
    }
    undoStack.removeLast()
    redoStack.append(command)
    refreshState()
    return true
  }

  @discardableResult
  func redo() async -> Bool {
    guard !isApplyingHistory, let command = redoStack.last else { return false }
    isApplyingHistory = true
    let didCommit = await command.redo()
    isApplyingHistory = false
    guard didCommit else {
      refreshState()
      return false
    }
    redoStack.removeLast()
    undoStack.append(command)
    refreshState()
    return true
  }

  func removeCommands(scope: UUID) {
    let removedCommand =
      undoStack.contains { $0.scope == scope }
      || redoStack.contains { $0.scope == scope }
    undoStack.removeAll { $0.scope == scope }
    redoStack.removeAll { $0.scope == scope }
    refreshState()
    if removedCommand {
      notifyDiscardedScopes([scope])
    }
  }

  func removeAllCommands() {
    let discardedScopes = Set((undoStack + redoStack).map(\.scope))
    undoStack.removeAll()
    redoStack.removeAll()
    refreshState()
    notifyDiscardedScopes(discardedScopes)
  }

  func retainedAttachmentFilenames(scope: UUID) -> Set<String> {
    (undoStack + redoStack)
      .filter { $0.scope == scope }
      .reduce(into: Set<String>()) { filenames, command in
        filenames.formUnion(command.referencedAttachmentFilenames)
      }
  }

  func setDiscardHandler(_ handler: @escaping (Set<UUID>) -> Void) {
    onDiscardedScopes = handler
  }

  private func refreshState() {
    canUndo = !undoStack.isEmpty
    canRedo = !redoStack.isEmpty
  }

  private func trimUndoStackToBudget() -> Set<UUID> {
    var discardedScopes: Set<UUID> = []
    while undoStack.count > limit || estimatedByteCost(of: undoStack) > byteLimit {
      guard !undoStack.isEmpty else { return discardedScopes }
      discardedScopes.insert(undoStack.removeFirst().scope)
    }
    return discardedScopes
  }

  private func estimatedByteCost(of commands: [Command]) -> Int {
    commands.reduce(0) { total, command in
      let (sum, overflow) = total.addingReportingOverflow(command.estimatedByteCost)
      return overflow ? .max : sum
    }
  }

  private func notifyDiscardedScopes(_ scopes: Set<UUID>) {
    guard !scopes.isEmpty else { return }
    onDiscardedScopes?(scopes)
  }
}
