import Foundation
import FandyCore

enum LeaseAdmission {
    static func automaticAlreadyVerified(_ status: HelperStatus, now: Double) -> Bool {
        guard status.version == Wire.version, status.automaticVerified, status.manualQualified,
              !status.observationOnly, status.fault == nil, status.recoveryBlocker == nil,
              status.restoration?.verified != false, let snapshot = status.snapshot,
              (try? snapshot.validateFans(now: now)) != nil else { return false }
        return snapshot.fans.allSatisfy { $0.mode == .automatic }
    }
}

/// Reuse only an immediately issued observation; the helper still acquires and
/// validates independent hardware readings before every write.
enum TargetObservation {
    static func snapshot(_ status: HelperStatus?, now: Double, required: Set<SensorRole>) -> HardwareSnapshot? {
        guard let status, status.version == Wire.version, status.manualQualified, !status.observationOnly,
              status.fault == nil, status.recoveryBlocker == nil, let snapshot = status.snapshot,
              now.isFinite, snapshot.sampledAt.isFinite, now >= snapshot.sampledAt,
              now - snapshot.sampledAt <= 0.25,
              (try? snapshot.validate(now: now, required: required)) != nil else { return nil }
        return snapshot
    }
}

enum LeaseContinuation {
    static func permits(_ lease: ControlLease, status: HelperStatus, required: Set<SensorRole>, now: Double) -> Bool {
        guard lease.expiresAt == nil, lease.required == required, !status.automaticVerified,
              let snapshot = TargetObservation.snapshot(status, now: now, required: required) else { return false }
        return snapshot.fans.allSatisfy { $0.mode == .manual }
    }
}

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
