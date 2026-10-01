import Foundation

/// Inert admission for the interval between automatic ownership and a fully manual test.
/// The hardware implementation must supply a separately reviewed target/mode transaction.
/// This model performs no writes and is not exposed over XPC.
public struct ManualQualificationActivation: Sendable {
    public let plan: ManualQualificationPlan
    public private(set) var stopReason: QualificationStop?
    public private(set) var activatedFanIDs: Set<Int> = []
    private var pending: FanTarget?
    private var lastChecked: Double
    private var lastSnapshot: HardwareSnapshot

    public init(plan: ManualQualificationPlan) {
        self.plan = plan; lastChecked = plan.startedAt; lastSnapshot = plan.baseline
    }

    /// Recheck fresh hardware immediately before starting the next fan transaction.
    /// Targets are fixed by the helper's original plan and cannot be replaced by callers.
    public mutating func authorizeNext(snapshot: HardwareSnapshot, now: Double) throws -> FanTarget {
        guard pending == nil else { stop(.malformedRequest); throw ControlError.staleSession }
        try validate(snapshot, now: now)
        guard let target = plan.targets.first(where: { !activatedFanIDs.contains($0.fanID) }),
              let fan = snapshot.fans.first(where: { $0.id == target.fanID }),
              fan.actualRPM > 0, target.rpm > fan.actualRPM else {
            stop(.hardwareChanged); throw ControlError.invalidFan
        }
        pending = target
        return target
    }

    /// Recheck immediately after the potentially blocking hardware operation. Passing the
    /// original deadline revokes admission before another fan can be touched.
    public mutating func didActivate(snapshot: HardwareSnapshot, now: Double) throws {
        guard let target = pending else { stop(.malformedRequest); throw ControlError.staleSession }
        activatedFanIDs.insert(target.fanID)
        pending = nil
        try validate(snapshot, now: now)
    }

    public mutating func finish(snapshot: HardwareSnapshot, now: Double) throws -> ManualQualificationSession {
        guard pending == nil, activatedFanIDs == Set(plan.targets.map(\.fanID)) else {
            stop(.malformedRequest); throw ControlError.staleSession
        }
        try validate(snapshot, now: now)
        var session = ManualQualificationSession(plan: plan)
        guard session.check(snapshot: snapshot, now: now) == nil else { throw ControlError.staleSession }
        return session
    }

    /// Revocation is an instruction to restore every fan, not a claim that release succeeded.
    public mutating func stop(_ reason: QualificationStop) {
        if stopReason == nil { stopReason = reason }
        pending = nil
    }

    private mutating func validate(_ snapshot: HardwareSnapshot, now: Double) throws {
        guard stopReason == nil else { throw ControlError.staleSession }
        guard now.isFinite, now >= lastChecked else { stop(.invalidClock); throw ControlError.invalidNumber }
        lastChecked = now
        guard now < plan.deadline else { stop(.deadline); throw ControlError.staleSession }
        do { try ManualQualificationPlan.validateReadings(snapshot, now: now) }
        catch { stop(.sensorFailure); throw error }
        guard snapshot.fans.count == plan.baseline.fans.count,
              snapshot.fans.allSatisfy({ fan in
                  plan.baseline.fans.contains { $0.id == fan.id && $0.minimumRPM == fan.minimumRPM && $0.maximumRPM == fan.maximumRPM }
              }) else { stop(.hardwareChanged); throw ControlError.invalidFan }
        for fan in snapshot.fans {
            let expected: FanMode = activatedFanIDs.contains(fan.id) ? .manual : .automatic
            guard fan.mode == expected else { stop(.ownershipConflict); throw ControlError.restorationUnverified }
            if expected == .manual {
                guard let target = plan.targets.first(where: { $0.fanID == fan.id }),
                      let observedTarget = fan.targetRPM, observedTarget.isFinite,
                      abs(observedTarget - target.rpm) <= 0.5 else {
                    stop(.ownershipConflict); throw ControlError.restorationUnverified
                }
            }
        }
        if snapshot.id != lastSnapshot.id {
            guard snapshot.sampledAt > lastSnapshot.sampledAt,
                  HardwareCapabilities.requiredRoles.allSatisfy({ role in
                      guard let next = snapshot.sensors.first(where: { $0.role == role }),
                            let previous = lastSnapshot.sensors.first(where: { $0.role == role }) else { return false }
                      return next.sequence > previous.sequence && next.sampledAt > previous.sampledAt
                  }) else { stop(.sensorFailure); throw ControlError.invalidSnapshot }
        } else if snapshot != lastSnapshot { stop(.sensorFailure); throw ControlError.invalidSnapshot }
        lastSnapshot = snapshot
    }
}
