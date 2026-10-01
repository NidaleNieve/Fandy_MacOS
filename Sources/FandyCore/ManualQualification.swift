import Foundation

/// Pure admission/deadline model. No hardware I/O, XPC entry point or physical writer is attached.
/// A future helper must construct this from its own signed capabilities and fresh hardware read.
public struct ManualQualificationPlan: Sendable, Equatable {
    public enum Trial: Sendable { case initial, recovery }
    public let id: UUID
    public let owner: UUID
    public let startedAt: Double
    public let deadline: Double
    public let baseline: HardwareSnapshot
    public let targets: [FanTarget]

    public init(capabilities: HardwareCapabilities, actualModel: String, owner: UUID,
                trial: Trial, snapshot: HardwareSnapshot, now: Double, automaticVerified: Bool) throws {
        guard capabilities.forMachine(actualModel).canQualifyManual else { throw ControlError.hardwareUnqualified }
        guard automaticVerified else { throw ControlError.restorationUnverified }
        try Self.validateReadings(snapshot, now: now)
        guard snapshot.fans.allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
        // Calculate all targets before admitting either fan. Never clamp a +200 request into
        // a downward request, substitute minimum RPM for a stopped fan, or issue a partial trial.
        targets = try snapshot.fans.map { fan in
            let rpm = fan.actualRPM + 200
            guard fan.actualRPM > 0, rpm.isFinite, rpm > fan.actualRPM, rpm >= fan.minimumRPM, rpm <= fan.maximumRPM else {
                throw ControlError.invalidFan
            }
            return FanTarget(fan.id, rpm)
        }
        id = UUID(); self.owner = owner; baseline = snapshot; startedAt = now
        deadline = now + (trial == .initial ? 5 : 15)
        guard deadline.isFinite, deadline > now else { throw ControlError.invalidNumber }
    }

    static func validateReadings(_ snapshot: HardwareSnapshot, now: Double) throws {
        try snapshot.validate(now: now, required: HardwareCapabilities.requiredRoles)
        // Conservative test admission ceiling, not an Apple critical-temperature assertion.
        guard now - snapshot.sampledAt <= 2 else { throw ControlError.invalidSnapshot }
        for role in HardwareCapabilities.requiredRoles {
            guard let reading = snapshot.sensors.first(where: { $0.role == role }) else { throw ControlError.sensorUnavailable(role) }
            guard try reading.value(now: now, maxAge: 2) < 75 else { throw ControlError.thermalPressure }
        }
    }
}

public enum QualificationStop: String, Sendable {
    case deadline, heartbeat, disconnected, powerTransition, malformedRequest
    case sensorFailure, ownershipConflict, hardwareChanged, invalidClock
}

/// One-use session. Starting a new session requires a separate, verified restoration.
/// Heartbeats cannot extend the absolute deadline. Stopping revokes authority immediately;
/// reporting successful handback is the responsibility of independent per-fan readback.
public struct ManualQualificationSession: Sendable {
    public let plan: ManualQualificationPlan
    public private(set) var stopReason: QualificationStop?
    public private(set) var lastHeartbeat: Double
    private var lastChecked: Double
    private var lastSnapshot: HardwareSnapshot
    public init(plan: ManualQualificationPlan) {
        self.plan = plan; lastHeartbeat = plan.startedAt; lastChecked = plan.startedAt
        lastSnapshot = plan.baseline
    }
    public var active: Bool { stopReason == nil }
    public mutating func stop(_ reason: QualificationStop) { if stopReason == nil { stopReason = reason } }
    public mutating func disconnect(owner: UUID) { if owner == plan.owner { stop(.disconnected) } }

    /// Call before every further command and from the independent helper watchdog.
    /// A nil reading, changing topology, unqualified sensor or nonadvancing acquisition fails closed.
    @discardableResult public mutating func check(snapshot: HardwareSnapshot?, now: Double) -> QualificationStop? {
        guard active else { return stopReason }
        guard now.isFinite, now >= lastChecked else { stop(.invalidClock); return stopReason }
        lastChecked = now
        if now >= plan.deadline { stop(.deadline); return stopReason }
        if now - lastHeartbeat >= 10 { stop(.heartbeat); return stopReason }
        guard let snapshot else { stop(.sensorFailure); return stopReason }
        do { try ManualQualificationPlan.validateReadings(snapshot, now: now) }
        catch { stop(.sensorFailure); return stopReason }
        guard snapshot.fans.count == plan.baseline.fans.count,
              snapshot.fans.allSatisfy({ fan in
                  plan.baseline.fans.contains { $0.id == fan.id && $0.minimumRPM == fan.minimumRPM && $0.maximumRPM == fan.maximumRPM }
              }) else { stop(.hardwareChanged); return stopReason }
        guard snapshot.fans.allSatisfy({ $0.mode == .manual }) else { stop(.ownershipConflict); return stopReason }
        // The same acquisition may be checked twice while still fresh. A different snapshot
        // must advance each required sensor's acquisition sequence and timestamp.
        if snapshot.id != lastSnapshot.id {
            guard snapshot.sampledAt > lastSnapshot.sampledAt,
                  HardwareCapabilities.requiredRoles.allSatisfy({ role in
                      guard let next = snapshot.sensors.first(where: { $0.role == role }),
                            let previous = lastSnapshot.sensors.first(where: { $0.role == role }) else { return false }
                      return next.sequence > previous.sequence && next.sampledAt > previous.sampledAt
                  }) else { stop(.sensorFailure); return stopReason }
        } else if snapshot != lastSnapshot { stop(.sensorFailure); return stopReason }
        lastSnapshot = snapshot
        return nil
    }

    public mutating func heartbeat(owner: UUID, sessionID: UUID, snapshot: HardwareSnapshot?, now: Double) throws {
        guard owner == plan.owner else { throw ControlError.unauthorized }
        guard sessionID == plan.id else { stop(.malformedRequest); throw ControlError.staleSession }
        guard check(snapshot: snapshot, now: now) == nil else { throw ControlError.staleSession }
        lastHeartbeat = now
    }
}
