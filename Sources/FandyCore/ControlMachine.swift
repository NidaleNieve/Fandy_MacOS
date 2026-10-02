import Foundation
public enum ControllerState: String, Codable, Sendable { case system, initializingCustom, customActive, restoringSystem, fault }
public enum ControlEffect: Sendable, Equatable {
    case none
    case restore(generation: UInt64)
    case apply(targets: [FanTarget], generation: UInt64, snapshotID: UUID, required: Set<SensorRole>)
}
public struct ControlMachine: Sendable {
    public private(set) var state: ControllerState = .system
    public private(set) var selected: Profile = BuiltInProfiles.system
    public private(set) var generation: UInt64 = 0
    public private(set) var fault: String?
    public private(set) var percent: Double = 0
    public private(set) var automaticAtIdle = false
    private var governor = DemandGovernor()
    private var healthyCount = 0
    private var lastHealthySample: UUID?
    private var zeroSince: Double?
    private var demandSince: Double?
    private var restorationIsFault = false
    public let chipPolicy: ChipControlPolicy
    public init(chipPolicy: ChipControlPolicy = .cpuGPU) { self.chipPolicy = chipPolicy }
    public mutating func select(_ profile: Profile) throws -> ControlEffect {
        try profile.validate() // Invalid edits never replace the running configuration.
        guard generation < UInt64.max else { throw ControlError.staleSession }
        generation += 1
        let wasSameCustom = selected.id == profile.id && state == .customActive
        selected = profile; fault = nil; restorationIsFault = false
        zeroSince = nil; demandSince = nil; automaticAtIdle = false
        if profile.kind == .system { state = .restoringSystem; return .restore(generation: generation) }
        if !wasSameCustom { healthyCount = 0; lastHealthySample = nil; governor.reset(percent); state = .initializingCustom }
        return .none
    }
    public mutating func fail(_ error: Error) -> ControlEffect {
        generation &+= 1
        fault = error.localizedDescription; selected = BuiltInProfiles.system; state = .restoringSystem
        restorationIsFault = true; automaticAtIdle = false; healthyCount = 0; lastHealthySample = nil
        return .restore(generation: generation)
    }
    public mutating func sleep() -> ControlEffect { fail(ControlError.invalidProfile("Sleep/wake reset; select a profile to resume.")) }
    public mutating func step(_ snapshot: HardwareSnapshot, now: Double) -> ControlEffect {
        if state == .restoringSystem || state == .fault { return .restore(generation: generation) }
        guard selected.kind != .system else { return .none }
        do {
            let demand = try ProfileEngine().evaluate(selected, snapshot: snapshot, now: now, chipPolicy: chipPolicy)
            if snapshot.id != lastHealthySample { healthyCount += 1; lastHealthySample = snapshot.id }
            if state == .initializingCustom && healthyCount < (selected.kind == .maximum ? 1 : 5) { return .none }
            if state == .initializingCustom && selected.automaticAtIdle && demand.percent == 0 {
                automaticAtIdle = true; state = .restoringSystem; return .restore(generation: generation)
            }
            if automaticAtIdle {
                if demand.percent >= 5 {
                    if demandSince == nil { demandSince = now }
                    if demand.safetyPercent == 0 && now - demandSince! < 3 { return .none }
                    automaticAtIdle = false; demandSince = nil
                } else { demandSince = nil; return .none }
            }
            if selected.automaticAtIdle && demand.percent == 0 {
                if zeroSince == nil { zeroSince = now }
                if now - zeroSince! >= 15 {
                    automaticAtIdle = true; state = .restoringSystem; return .restore(generation: generation)
                }
            } else { zeroSince = nil }
            percent = try governor.update(demand.percent, at: now, urgent: selected.kind == .maximum || demand.safetyPercent > percent)
            // An independent safety request may never be attenuated by the acoustic governor.
            percent = max(percent, demand.safetyPercent)
            let targets = try snapshot.fans.map { FanTarget($0.id, try $0.rpm(percent: percent)) }
            return .apply(targets: targets, generation: generation, snapshotID: snapshot.id, required: selected.requiredSensors(chipPolicy: chipPolicy))
        } catch { return fail(error) }
    }
    public mutating func applied(generation reply: UInt64) {
        guard reply == generation, selected.kind != .system, !automaticAtIdle, state != .fault, state != .restoringSystem else { return }
        state = .customActive
    }
    public mutating func restored(generation reply: UInt64, verified: Bool) {
        guard reply == generation else { return }
        guard verified else { state = .fault; fault = ControlError.restorationUnverified.localizedDescription; return }
        governor.reset(); percent = 0
        if automaticAtIdle && selected.kind != .system { state = .customActive }
        else { state = .system; if !restorationIsFault { fault = nil } }
    }
}

/// Timestamp advancement detects stale acquisition; identical temperatures are not automatically failures.
public struct SensorFreshnessMonitor: Sendable {
    private var lastSequence: [SensorRole: UInt64] = [:]
    private var progressAt: [SensorRole: Double] = [:]
    public init() {}
    public mutating func check(_ snapshot: HardwareSnapshot, required: Set<SensorRole>, now: Double) throws {
        for role in required {
            _ = try snapshot.value(role, now: now)
            guard let reading = snapshot.sensors.first(where: { $0.role == role }) else { throw ControlError.sensorUnavailable(role) }
            if lastSequence[role] != reading.sequence { lastSequence[role] = reading.sequence; progressAt[role] = now }
            if progressAt[role] == nil { progressAt[role] = now }
            guard now - progressAt[role]! <= 3 else { throw ControlError.sensorUnavailable(role) }
        }
    }
}
