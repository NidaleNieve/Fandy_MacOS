import Foundation

/// Called only on the helper's serial queue. Owns all leases and hardware effects.
/// Injected I/O makes every failure path testable without physical fan writes.
public final class HelperCoordinator: @unchecked Sendable {
    private let io: any FanHardwareIO
    private let read: () throws -> HardwareSnapshot
    private let clock: () -> Double
    private let qualified: Bool
    private let writesPermitted: Bool
    private let event: (String) -> Void
    private let requireExclusive: () throws -> Void
    private var safety = HelperSafety()
    private var freshness = SensorFreshnessMonitor()
    private var samples: [HardwareSnapshot] = []
    private var healthy = 0
    private var targets: [FanTarget] = []
    private var leaseFans: [Fan] = []
    private var qualificationFloors: [Int: Double] = [:]
    private var targetsStartedAt: Double?
    private var lastWatchdogObservationAt: Double?
    /// Expiry/release decisions run every 100ms; full SMC acquisition is bounded to 2Hz.
    private let watchdogObservationInterval = 0.5
    private var fault: String?
    private var restoration: RestorationReport?
    private var startupRestoration: RestorationReport?
    public var lastRestoration: RestorationReport? { restoration }
    /// Read only on the serial hardware queue when tagging watchdog work.
    public var leaseOwner: UUID? { safety.lease?.owner }
    private let capabilities: HardwareCapabilities
    public init(io: any FanHardwareIO, capabilities: HardwareCapabilities, read: @escaping () throws -> HardwareSnapshot,
                clock: @escaping () -> Double, event: @escaping (String) -> Void = { _ in }, requireExclusive: @escaping () throws -> Void = {}) {
        self.requireExclusive = requireExclusive; self.capabilities = capabilities; self.io = io; self.qualified = capabilities.canControl
        self.writesPermitted = capabilities.canRestore; self.read = read; self.clock = clock; self.event = event
        self.safety = HelperSafety(chipPolicy: capabilities.chipPolicy)
        // Hardware callbacks run only on the same serial helper queue. No IPC caller
        // can provide this closure or select the compiled guard policy.
        io.setGuardEvaluator { [weak self] snapshot, now in
            guard let self else { throw ControlError.helperUnavailable }
            return try self.safety.observeChipGuard(snapshot, now: now).enforcedPercent
        }
    }
    @discardableResult public func startup() -> Bool {
        let result = restore(); startupRestoration = restoration; return result
    }
    @discardableResult public func restore() -> Bool {
        guard writesPermitted else {
            safety.revoke(); fault = ControlError.hardwareUnqualified.localizedDescription
            return false
        }
        event("Restoring automatic fan control"); safety.revoke(); targets = []; leaseFans = []; targetsStartedAt = nil; lastWatchdogObservationAt = nil; qualificationFloors = [:]; restoration = nil
        do {
            restoration = try FanRestoration.report(using: io)
            if let report = restoration, let data = try? JSONEncoder().encode(report), let text = String(data: data, encoding: .utf8) { event("Restoration report: " + text) }
            guard restoration?.verified == true else { throw ControlError.restorationUnverified }
            safety.restorationFinished(true); fault = nil; event("Automatic fan ownership verified"); return true
        }
        catch { safety.restorationFinished(false); fault = error.localizedDescription; event("Automatic restoration unverified: \(error.localizedDescription)"); return false }
    }
    public func powerTransition() { healthy = 0; samples = []; freshness = SensorFreshnessMonitor(); _ = restore() }
    private func acquire() throws -> HardwareSnapshot {
        do {
        let snapshot = try read()
        try recordHealthy(snapshot)
        return snapshot
        } catch { healthy = 0; samples = []; throw error }
    }
    private func recordHealthy(_ snapshot: HardwareSnapshot) throws {
        samples.append(snapshot); samples = Array(samples.filter { clock() - $0.sampledAt <= 3 }.suffix(32))
        try snapshot.validate(now: clock(), required: safety.lease?.required ?? [])
        if capabilities.stage == .curveQualification, safety.lease?.required.isEmpty == false {
            guard try capabilities.chipPolicy.temperature(in: snapshot, now: clock()) < MeasurementSafety.ceilingC else { throw ControlError.thermalPressure }
        }
        if safety.lease != nil {
            guard snapshot.fans.count == leaseFans.count, snapshot.fans.allSatisfy({ fan in leaseFans.contains { $0.id == fan.id && $0.minimumRPM == fan.minimumRPM && $0.maximumRPM == fan.maximumRPM } }) else { throw ControlError.invalidFan }
        }
        try freshness.check(snapshot, required: safety.lease?.required ?? [], now: clock())
        if (try? capabilities.chipPolicy.temperature(in: snapshot, now: clock())) != nil {
            _ = try safety.observeChipGuard(snapshot, now: clock())
        }
        healthy = min(5, healthy + 1)
    }
    public func status() -> HelperStatus {
        if !writesPermitted { return observationStatus() }
        // Status never renews a lease. It also detects a conflicting controller changing ownership.
        var observedSnapshot: HardwareSnapshot?
        do {
            let snapshot: HardwareSnapshot
            if safety.lease == nil {
                snapshot = try read()
                observedSnapshot = snapshot
                try snapshot.validateFans(now: clock())
                do { try recordHealthy(snapshot) } catch { healthy = 0; samples = [] }
            } else { snapshot = try acquire() }
            if safety.lease != nil {
                try safety.requireLiveLease(at: clock())
                guard snapshot.fans.allSatisfy({ fan in targets.isEmpty ? fan.mode.isAutomatic : ownsTarget(fan) }) else { throw ControlError.restorationUnverified }
            }
            if safety.lease == nil {
                let automatic = !safety.restoring && snapshot.appleOwnershipObserved
                safety.observeIdleOwnership(automatic)
                fault = automatic ? nil : ControlError.restorationUnverified.localizedDescription
            }
            var status = HelperStatus(automaticVerified: safety.systemVerified, manualQualified: qualified, snapshot: snapshot, fault: fault, capabilities: capabilities, restoration: restoration, startupRestoration: startupRestoration)
            status.chipGuard = safety.guardReading; return status
        } catch {
            if safety.lease != nil { _ = restore() }
            else { safety.observationFailed() }
            // Keep independently readable temperatures, but never expose invalid/stale fan
            // telemetry as proof of ownership after the failed validation.
            observedSnapshot?.fans = []
            return HelperStatus(automaticVerified: safety.systemVerified, manualQualified: qualified, snapshot: observedSnapshot, fault: error.localizedDescription, capabilities: capabilities, restoration: restoration, startupRestoration: startupRestoration)
        }
    }
    private func observationStatus() -> HelperStatus {
        do {
            let snapshot = try read()
            if snapshot.fans.isEmpty {
                return HelperStatus(automaticVerified: false, observationOnly: true, snapshot: snapshot,
                    fault: "Fan interface unavailable; temperature monitoring remains available.", capabilities: capabilities)
            }
            try snapshot.validateFans(now: clock())
            let automatic = snapshot.appleOwnershipObserved
            return HelperStatus(automaticVerified: automatic, observationOnly: true, snapshot: snapshot,
                                fault: automatic ? nil : "External manual fan control observed; observation helper cannot change it.", capabilities: capabilities)
        } catch {
            return HelperStatus(automaticVerified: false, observationOnly: true, fault: error.localizedDescription, capabilities: capabilities)
        }
    }
    public func begin(_ request: LeaseRequest, owner: UUID) throws -> ControlLease {
        guard qualified, capabilities.permits(required: request.required) else { throw ControlError.hardwareUnqualified }
        try requireExclusive()
        guard request.version == Wire.version, request.required.count <= SensorRole.allCases.count else { throw ControlError.malformedMessage }
        let snapshot = try acquire()
        guard healthy >= (request.required.isEmpty ? 1 : 5) else { throw ControlError.invalidSnapshot }
        guard snapshot.appleOwnershipObserved else { throw ControlError.restorationUnverified }
        targets = []
        let qualifying = capabilities.stage == .curveQualification && !request.required.isEmpty
        if qualifying {
            guard try capabilities.chipPolicy.temperature(in: snapshot, now: clock()) < MeasurementSafety.ceilingC else { throw ControlError.thermalPressure }
        }
        qualificationFloors = [:]
        if qualifying {
            for fan in snapshot.fans {
                let minimum = max(fan.minimumRPM, fan.actualRPM) + 200
                guard minimum <= fan.maximumRPM else { throw ControlError.invalidFan }
                qualificationFloors[fan.id] = minimum
            }
        }
        let lease = try safety.begin(owner: owner, generation: request.generation, required: request.required, snapshot: snapshot, now: clock(), qualification: qualifying)
        leaseFans = snapshot.fans
        return lease
    }
    public func apply(_ request: TargetRequest, owner: UUID) throws {
        do {
            try requireExclusive()
            guard qualified, request.version == Wire.version,
                  samples.contains(where: { $0.id == request.snapshotID && clock() - $0.sampledAt <= 3 }) else { throw ControlError.malformedMessage }
            let snapshot = try acquire()
            if !targets.isEmpty {
                guard snapshot.fans.allSatisfy({ ownsTarget($0) }) else { throw ControlError.restorationUnverified }
            }
            if !qualificationFloors.isEmpty {
                guard request.targets.allSatisfy({ target in
                    qualificationFloors[target.fanID].map { target.rpm >= $0 } ?? false
                }) else { throw ControlError.invalidFan }
            }
            let requested = try safety.validateAndRenew(owner: owner, leaseID: request.leaseID, generation: request.generation, targets: request.targets, snapshot: snapshot, now: clock())
            let validated = try normalized(requested, fans: snapshot.fans)
            // Reserve the physical batch's two-second budget inside the nonrenewable trial.
            if let deadline = safety.lease?.expiresAt {
                guard deadline - clock() >= 2 else { throw ControlError.staleSession }
            }
            try safety.requireLiveLease(at: clock())
            io.setControlRequirements(safety.lease?.required ?? [])
            try FanRestoration.apply(validated, using: io)
            try safety.requireLiveLease(at: clock())
            _ = try acquire() // Required sensors and bounds must still be healthy after I/O.
            try safety.requireLiveLease(at: clock())
            if targets.isEmpty { targetsStartedAt = clock() }
            targets = validated
        } catch {
            if safety.lease?.owner == owner { _ = restore() }
            throw error
        }
    }
    private func ownsTarget(_ fan: Fan) -> Bool {
        guard fan.mode == .manual, let observed = fan.targetRPM,
              let requested = targets.first(where: { $0.fanID == fan.id }) else { return false }
        return abs(observed - requested.rpm) <= 0.5
    }
    private func normalized(_ requested: [FanTarget], fans: [Fan]) throws -> [FanTarget] {
        let result = try io.normalizedTargets(requested)
        guard result.count == requested.count, Set(result.map(\.fanID)) == Set(requested.map(\.fanID)),
              Set(result.map(\.fanID)).count == result.count else { throw ControlError.invalidFan }
        for target in result {
            guard let source = requested.first(where: { $0.fanID == target.fanID }),
                  let fan = fans.first(where: { $0.id == target.fanID }),
                  target.rpm.isFinite, target.rpm >= source.rpm, target.rpm >= fan.minimumRPM,
                  target.rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
        }
        return result
    }
    public func disconnected(owner: UUID) { if safety.disconnect(owner: owner) { event("Controller disconnected"); _ = restore() } }
    public func reject(owner: UUID) { if safety.lease?.owner == owner { _ = restore() } }
    public func watchdog() {
        guard writesPermitted else { return }
        if safety.expired(at: clock()) { event("Heartbeat expired"); _ = restore(); return }
        if safety.restoring { _ = restore(); return }
        guard safety.lease != nil else { return }
        do {
            let now = clock()
            if let last = lastWatchdogObservationAt {
                guard now >= last else { throw ControlError.invalidNumber }
                if now - last < watchdogObservationInterval { return }
            }
            lastWatchdogObservationAt = now
            try requireExclusive()
            let snapshot = try acquire()
            try safety.requireLiveLease(at: clock())
            if targets.isEmpty {
                guard snapshot.appleOwnershipObserved else { throw ControlError.restorationUnverified }
                return
            }
            guard snapshot.fans.allSatisfy({ ownsTarget($0) }) else { throw ControlError.restorationUnverified }
            if let started = targetsStartedAt, clock() - started >= 10 {
                guard snapshot.fans.allSatisfy({ $0.actualRPM > 0 && $0.actualRPM >= $0.minimumRPM * 0.9 }) else { throw ControlError.invalidFan }
            }
            if safety.lease?.required.isEmpty == true { return } // Maximum needs no thermal identities.
            // Independent thermal escalation does not renew the GUI heartbeat.
            let percent = try safety.observeChipGuard(snapshot, now: clock()).enforcedPercent
            let elevated = try targets.map { target -> FanTarget in
                guard let fan = snapshot.fans.first(where: { $0.id == target.fanID }) else { throw ControlError.invalidFan }
                return FanTarget(target.fanID, max(target.rpm, try fan.rpm(percent: percent)))
            }
            let final = try normalized(elevated, fans: snapshot.fans)
            try safety.requireLiveLease(at: clock())
            if final != targets {
                try FanRestoration.apply(final, using: io)
                try safety.requireLiveLease(at: clock())
                targets = final
            }
        } catch { _ = restore() }
    }
}
