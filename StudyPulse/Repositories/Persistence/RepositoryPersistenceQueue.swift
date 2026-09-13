//
//  RepositoryPersistenceQueue.swift
//  StudyPulse
//
//  Serializes high-frequency repository writes and refuses to swallow
//  persistence failures: restore the in-memory snapshot, record lastError,
//  and rethrow from flush().
//

import Foundation
import os

enum RepositoryPersistenceError: Error, Equatable, LocalizedError {
    case executorNotAttached
    case mutationFailed(String)

    var errorDescription: String? {
        switch self {
        case .executorNotAttached:
            return "Persistence executor is not attached"
        case .mutationFailed(let message):
            return message
        }
    }
}

/// Serial write queue shared by Grade / Mistake / Exam / Task repositories.
@MainActor
final class RepositoryPersistenceQueue {
    private let domain: String
    private var tail: Task<Void, Never>?
    private(set) var lastError: (any Error)?
    /// Test-only: next queued operation throws before the SwiftData mutation.
    var debugNextOperationError: (any Error)?

    init(domain: String) {
        self.domain = domain
    }

    func enqueue(
        executor: PersistenceExecutor?,
        captureRestore: @escaping () -> () -> Void,
        onSettled: @escaping ((any Error)?) -> Void,
        operation: @escaping @MainActor @Sendable (PersistenceExecutor) async throws -> Void
    ) {
        guard let executor else {
            lastError = RepositoryPersistenceError.executorNotAttached
            onSettled(lastError)
            Log.data.error("\(self.domain, privacy: .public) persistence executor is not attached")
            return
        }

        let predecessor = tail
        tail = Task { @MainActor in
            await predecessor?.value
            guard !Task.isCancelled else { return }
            let restore = captureRestore()
            do {
                if let forcedError = self.debugNextOperationError {
                    self.debugNextOperationError = nil
                    throw forcedError
                }
                try await operation(executor)
                self.lastError = nil
                onSettled(nil)
            } catch is CancellationError {
                Log.data.debug("\(self.domain, privacy: .public) mutation cancelled")
            } catch {
                restore()
                self.lastError = error
                onSettled(error)
                Log.data.error(
                    "\(self.domain, privacy: .public) mutation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Waits for queued work without converting a prior failure into a throw.
    /// Used by `loadAll` so a failed mutation cannot skip the disk reload.
    func wait() async {
        await tail?.value
    }

    func flush() async throws {
        await wait()
        if let lastError {
            throw lastError
        }
    }

    func cancel() {
        tail?.cancel()
        tail = nil
    }
}
