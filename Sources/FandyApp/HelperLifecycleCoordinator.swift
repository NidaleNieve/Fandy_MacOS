import Foundation
import FandyCore

/// Main-actor service operations retain exclusivity across suspension points.
/// Different operations queue independently; none coalesce with an unrelated release.
@MainActor final class HelperLifecycleCoordinator {
    private(set) var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func run(_ operation: @MainActor () async throws -> Void) async throws {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
        defer {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        try await operation()
    }
    func perform(_ operation: () throws -> Void) throws {
        guard !busy else { throw ControlError.staleSession }
        busy = true; defer { busy = false }
        try operation()
    }
}
