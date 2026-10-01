import Foundation

public struct RecoveryObservation: Sendable {
    public var snapshot: HardwareSnapshot
    public var diagnosticPeak: Double
    public var diagnosticKeyCount: Int
    public init(snapshot: HardwareSnapshot, diagnosticPeak: Double, diagnosticKeyCount: Int) {
        self.snapshot = snapshot; self.diagnosticPeak = diagnosticPeak; self.diagnosticKeyCount = diagnosticKeyCount
    }
    public func validate(now: Double) throws {
        try snapshot.validateFans(now: now)
        guard now.isFinite, now - snapshot.sampledAt <= 2,
              snapshot.thermalPressure == .nominal || snapshot.thermalPressure == .fair,
              diagnosticKeyCount > 0, diagnosticPeak.isFinite, diagnosticPeak > 0, diagnosticPeak < 75 else {
            throw ControlError.invalidSnapshot
        }
        // Candidate identities remain unverified. Read health is checked without promoting
        // labels or granting profile authority. The wider raw-domain ceiling is diagnostic only.
        for role in HardwareCapabilities.requiredRoles {
            let matches = snapshot.sensors.filter { $0.role == role }
            guard matches.count == 1, let reading = matches.first,
                  reading.health == .valid || reading.health == .unverified,
                  let value = reading.celsius, value.isFinite, value > 0, value < 75,
                  reading.sampledAt.isFinite, now >= reading.sampledAt, now - reading.sampledAt <= 2 else {
                throw ControlError.sensorUnavailable(role)
            }
        }
    }
}

public struct RecoveryTrialRequest: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case initial, recovery, heartbeat }
    public var version: Int = Wire.version
    public var action: Action
    public var sessionID: UUID?
    public init(_ action: Action, sessionID: UUID? = nil) { self.action = action; self.sessionID = sessionID }
    public static func decode(_ data: Data) throws -> Self {
        let value = try Wire.decode(Self.self, from: data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "action", "sessionID"]), value.version == Wire.version,
              (value.action == .heartbeat) == (value.sessionID != nil) else { throw ControlError.malformedMessage }
        return value
    }
}

public struct RecoveryTrialStep: Codable, Sendable {
    public var name: String
    public var time: Double
    public var fanID: Int?
    public var fans: [Fan]?
}

public enum RecoveryTrialError: Error, LocalizedError {
    case modeMismatch(fanID: Int, observed: FanMode)
    case targetMismatch(fanID: Int, expected: Double, observed: Double?)
    public var errorDescription: String? {
        switch self {
        case .modeMismatch(let id, let mode): "Recovery fan \(id): unexpected mode \(mode.rawValue)"
        case .targetMismatch(let id, let expected, let observed): "Recovery fan \(id): target readback \(observed.map(String.init(describing:)) ?? "unavailable"), expected \(expected) RPM"
        }
    }
}

public struct RecoveryTrialStatus: Codable, Sendable {
    public var id: UUID
    public var active: Bool
    public var startedAt: Double
    public var deadline: Double
    public var targets: [FanTarget]
    public var baselineFans: [Fan]
    public var reason: String?
    public var failure: String?
    public var restoredAt: Double?
    public var restoration: RestorationReport?
    public var steps: [RecoveryTrialStep]? = []
    public var activationPath: String?
    public var firstRestoration: RestorationReport?
}

/// The implementation is helper-private. These methods are never arbitrary XPC commands.
public protocol RecoveryFanHardwareIO: FanHardwareIO {
    func prepareRecoveryTarget(_ target: FanTarget, deadline: Double) throws
    func activateRecoveryFan(_ target: FanTarget, deadline: Double) throws
    func startStoppedRecoveryFan(_ target: FanTarget, deadline: Double) throws
}
public extension RecoveryFanHardwareIO {
    func startStoppedRecoveryFan(_ target: FanTarget, deadline: Double) throws { throw ControlError.hardwareUnqualified }
}

/// Serial helper-owned, finite mechanical trials. General profiles remain disabled.
/// A blocked/dead helper cannot execute its timer; checks run again whenever I/O returns.
public final class RecoveryTrialCoordinator {
    private let io: any RecoveryFanHardwareIO
    private let capabilities: HardwareCapabilities
    private let read: () throws -> RecoveryObservation
    private let clock: () -> Double
    private let restore: () -> RestorationReport?
    private let requireExclusive: () throws -> Void
    private var owner: UUID?
    private var lastHeartbeat = 0.0
    private var lastClock = 0.0
    private var lastSnapshot: HardwareSnapshot?
    private var needsRestoration = false
    private var initialUsed = false
    private var initialPassed = false
    private var initialAttempt = false
    private var fullyActivated = false
    private var recoveryCount = 0
    public private(set) var status: RecoveryTrialStatus?
    public init(io: any RecoveryFanHardwareIO, capabilities: HardwareCapabilities,
                read: @escaping () throws -> RecoveryObservation, clock: @escaping () -> Double,
                restore: @escaping () -> RestorationReport?, requireExclusive: @escaping () throws -> Void = {}) {
        self.io = io; self.capabilities = capabilities; self.read = read; self.clock = clock; self.restore = restore; self.requireExclusive = requireExclusive
    }
    public func request(_ request: RecoveryTrialRequest, owner caller: UUID) throws -> RecoveryTrialStatus {
        guard capabilities.canQualifyRecovery else { throw ControlError.hardwareUnqualified }
        guard request.version == Wire.version else { throw ControlError.malformedMessage }
        if request.action == .heartbeat {
            guard owner == caller else { throw ControlError.unauthorized }
            guard request.sessionID == status?.id else { _ = release(reason: "malformed heartbeat"); throw ControlError.staleSession }
            do { try checkActive(); lastHeartbeat = clock(); return status! }
            catch { _ = release(reason: "heartbeat rejected", failure: error); throw error }
        }
        guard request.sessionID == nil, owner == nil, !needsRestoration else { throw ControlError.staleSession }
        guard request.action == .initial ? !initialUsed : initialPassed && recoveryCount < 8 else { throw ControlError.staleSession }
        try requireExclusive()
        guard restore()?.verified == true else { throw ControlError.restorationUnverified }
        let observation = try read(), now = clock()
        try observation.validate(now: now)
        let snapshot = observation.snapshot
        guard snapshot.fans.allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
        let targets = try snapshot.fans.map { fan -> FanTarget in
            // Starting a naturally stopped fan is an explicitly labelled mechanical trial,
            // not an invented 200 RPM command or a production minimum-floor claim.
            let rpm = max(fan.actualRPM, fan.minimumRPM) + 200
            guard rpm.isFinite, rpm > fan.actualRPM, rpm >= fan.minimumRPM, rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
            return FanTarget(fan.id, rpm)
        }
        if request.action == .initial { initialUsed = true } else { recoveryCount += 1 }
        status = RecoveryTrialStatus(id: UUID(), active: true, startedAt: now,
            deadline: now + (request.action == .initial ? 5 : 15), targets: targets, baselineFans: snapshot.fans)
        initialAttempt = request.action == .initial; fullyActivated = false
        owner = caller; lastClock = now; lastHeartbeat = now; lastSnapshot = snapshot
        var activated = Set<Int>()
        do {
            let stopped = snapshot.fans.allSatisfy { $0.actualRPM == 0 && $0.targetRPM == 0 }
            if stopped {
                // This is an explicit baseline-specific sequence, never a fallback after
                // failed preloading. Require a stricter diagnostic ceiling for first startup.
                guard observation.diagnosticPeak < 60 else { throw ControlError.invalidSnapshot }
                status?.activationPath = "stopped-zero-target mode-first"
                for target in targets {
                    try checkTransition(activated: activated, diagnosticCeiling: 60)
                    guard lastSnapshot?.fans.filter({ !activated.contains($0.id) }).allSatisfy({ $0.actualRPM == 0 && $0.targetRPM == 0 }) == true else {
                        throw ControlError.invalidFan
                    }
                    record("stopped start command", fanID: target.fanID, fans: lastSnapshot?.fans)
                    try io.startStoppedRecoveryFan(target, deadline: status!.deadline)
                    activated.insert(target.fanID)
                    try checkTransition(activated: activated, diagnosticCeiling: 60)
                    record("stopped start verified", fanID: target.fanID, fans: lastSnapshot?.fans)
                }
            } else {
                status?.activationPath = "automatic target preload"
                // A spinning baseline still requires target-first readback. Never switch
                // transaction order after a rejected or cleared preload.
                for target in targets {
                    try checkTransition(activated: activated)
                    record("prepare command", fanID: target.fanID)
                    try io.prepareRecoveryTarget(target, deadline: status!.deadline)
                    record("prepare accepted", fanID: target.fanID)
                    try checkTransition(activated: activated, prepared: target)
                    record("prepare verified", fanID: target.fanID, fans: lastSnapshot?.fans)
                }
                for target in targets {
                    try checkTransition(activated: activated, prepared: target)
                    record("manual command", fanID: target.fanID)
                    try io.activateRecoveryFan(target, deadline: status!.deadline)
                    record("manual accepted", fanID: target.fanID)
                    activated.insert(target.fanID)
                    try checkTransition(activated: activated)
                    record("manual verified", fanID: target.fanID, fans: lastSnapshot?.fans)
                }
            }
            try checkActive()
            fullyActivated = true
            return status!
        } catch { _ = release(reason: "activation failed", failure: error); throw error }
    }
    public func watchdog() {
        if needsRestoration { _ = release(reason: status?.reason ?? "restoration retry"); return }
        guard owner != nil else { return }
        do { try checkActive() }
        catch {
            let now = clock()
            let reason = status.map { now >= $0.deadline ? "deadline expired" : now - lastHeartbeat >= 10 ? "heartbeat expired" : "guard failed" } ?? "guard failed"
            _ = release(reason: reason, failure: reason == "guard failed" ? error : nil)
        }
    }
    public func disconnected(owner caller: UUID) { if owner == caller { _ = release(reason: "controller disconnected") } }
    public func reject(owner caller: UUID) { if owner == caller { _ = release(reason: "owned request rejected") } }
    @discardableResult public func release(reason: String, failure: (any Error)? = nil) -> Bool {
        owner = nil; status?.active = false
        if status?.reason == nil { status?.reason = reason }
        if let failure, status?.failure == nil { status?.failure = failure.localizedDescription }
        let report = restore()
        if status?.firstRestoration == nil { status?.firstRestoration = report }
        status?.restoration = report
        needsRestoration = report?.verified != true
        if !needsRestoration {
            status?.restoredAt = clock()
            if initialAttempt, fullyActivated, status?.failure == nil,
               status?.firstRestoration?.fans.allSatisfy(\.releasedManual) == true { initialPassed = true }
        }
        return !needsRestoration
    }
    private func record(_ name: String, fanID: Int? = nil, fans: [Fan]? = nil) {
        status?.steps?.append(RecoveryTrialStep(name: name, time: clock(), fanID: fanID, fans: fans))
    }
    private func checkActive() throws {
        guard let status, status.active, owner != nil else { throw ControlError.staleSession }
        try checkTransition(activated: Set(status.targets.map(\.fanID)))
    }
    private func checkTransition(activated: Set<Int>, prepared: FanTarget? = nil, diagnosticCeiling: Double = 75) throws {
        try requireExclusive()
        let now = clock()
        guard let status, now.isFinite, now >= lastClock, now < status.deadline,
              now - lastHeartbeat < 10 else { throw ControlError.staleSession }
        lastClock = now
        let observation = try read(), afterRead = clock()
        try observation.validate(now: afterRead)
        guard observation.diagnosticPeak < diagnosticCeiling else { throw ControlError.invalidSnapshot }
        guard afterRead.isFinite, afterRead >= now, afterRead < status.deadline,
              afterRead - lastHeartbeat < 10 else { throw ControlError.staleSession }
        lastClock = afterRead
        let next = observation.snapshot
        guard next.fans.count == status.baselineFans.count else { throw ControlError.invalidFan }
        for fan in next.fans {
            guard let baseline = status.baselineFans.first(where: { $0.id == fan.id }),
                  baseline.minimumRPM == fan.minimumRPM, baseline.maximumRPM == fan.maximumRPM,
                  let target = status.targets.first(where: { $0.fanID == fan.id }) else { throw ControlError.invalidFan }
            let manual = activated.contains(fan.id)
            guard fan.mode == (manual ? .manual : .automatic) else { throw RecoveryTrialError.modeMismatch(fanID: fan.id, observed: fan.mode) }
            if manual || prepared?.fanID == fan.id {
                guard let rpm = fan.targetRPM, abs(rpm - target.rpm) <= 0.5 else {
                    record("target readback failed", fanID: fan.id, fans: next.fans)
                    throw RecoveryTrialError.targetMismatch(fanID: fan.id, expected: target.rpm, observed: fan.targetRPM)
                }
            }
            if !manual { guard target.rpm > fan.actualRPM else { throw ControlError.invalidFan } }
        }
        if let previous = lastSnapshot {
            guard next.id != previous.id, next.sampledAt > previous.sampledAt,
                  HardwareCapabilities.requiredRoles.allSatisfy({ role in
                      guard let a = previous.sensors.first(where: { $0.role == role }),
                            let b = next.sensors.first(where: { $0.role == role }) else { return false }
                      return b.sequence > a.sequence && b.sampledAt > a.sampledAt
                  }) else { throw ControlError.invalidSnapshot }
        }
        lastSnapshot = next
    }
}
