import Foundation

/// Overlapping lifecycle requests share one release RPC. No success is cached after completion.
@MainActor final class RestorationFlight {
    private var pending: (id: UUID, task: Task<Void, any Error>)?
    func run(_ restore: @escaping @MainActor () async throws -> Void) async throws {
        let flight: (id: UUID, task: Task<Void, any Error>)
        if let pending { flight = pending }
        else {
            flight = (UUID(), Task { try await restore() })
            pending = flight
        }
        defer { if pending?.id == flight.id { pending = nil } }
        try await flight.task.value
    }
}
