import Foundation
public struct ControlLease: Codable, Sendable, Equatable {
    public var id: UUID
    public var owner: UUID
    public var generation: UInt64
    public var renewedAt: Double
    public var required: Set<SensorRole>
    public var expiresAt: Double? = nil
}
/// No physical I/O. The helper serializes these decisions with hardware effects.
public struct HelperSafety: Sendable {
    public private(set) var lease: ControlLease?
    private enum AutomaticState: Sendable { case unverified, restoring, observed }
    private var automaticState: AutomaticState = .restoring
    public var systemVerified: Bool { automaticState == .observed }
    public var restoring: Bool { automaticState == .restoring }
    public private(set) var generation: UInt64 = 0
    private var previousOwner: UUID?
    public let timeout: Double
    public let chipPolicy: ChipControlPolicy
    private var chipGuard = SmoothedChipGuard()
    public private(set) var guardReading: ChipGuardReading?
    public mutating func observeChipGuard(_ snapshot: HardwareSnapshot, now: Double) throws -> ChipGuardReading {
        let reading = try chipGuard.update(snapshot: snapshot, now: now, policy: chipPolicy)
        guardReading = reading; return reading
    }
    public init(timeout: Double = 10, chipPolicy: ChipControlPolicy = .cpuGPU) { self.timeout = timeout; self.chipPolicy = chipPolicy }
    public mutating func restorationFinished(_ verified: Bool) { automaticState = verified ? .observed : .restoring; if verified { lease = nil } }
    /// External ownership loss while idle is a conflict, not a failed release transaction.
    /// Observation must not start an automatic-write loop against another controller.
    public mutating func observeIdleOwnership(_ automatic: Bool) {
        guard lease == nil else { return }
        if !restoring { automaticState = automatic ? .observed : .unverified }
    }
    /// A failed idle observation invalidates evidence, not an ownership transaction.
    /// Preserve retries only when a real release was already pending.
    public mutating func observationFailed() {
        if !restoring { automaticState = .unverified }
    }
    public mutating func revoke() { lease = nil; automaticState = .restoring; chipGuard.reset(); guardReading = nil }
    public mutating func begin(owner: UUID, generation requested: UInt64, required: Set<SensorRole>, snapshot: HardwareSnapshot, now: Double, qualification: Bool = false) throws -> ControlLease {
        guard systemVerified, !restoring, lease == nil, (owner != previousOwner || requested >= generation) else { throw ControlError.staleSession }
        try snapshot.validate(now: now, required: required)
        generation = requested; previousOwner = owner
        let fresh = ControlLease(id: UUID(), owner: owner, generation: requested, renewedAt: now, required: required, expiresAt: qualification ? now + 15 : nil)
        lease = fresh; automaticState = .unverified
        return fresh
    }
    public mutating func validateAndRenew(owner: UUID, leaseID: UUID, generation requested: UInt64, targets: [FanTarget], snapshot: HardwareSnapshot, now: Double) throws -> [FanTarget] {
        guard var current = lease, current.owner == owner, current.id == leaseID,
              requested == current.generation, requested == generation, !restoring,
              now.isFinite, now >= current.renewedAt, now - current.renewedAt < timeout,
              current.expiresAt.map({ $0.isFinite && now < $0 }) ?? true else { throw ControlError.staleSession }
        try snapshot.validate(now: now, required: current.required)
        guard targets.count == snapshot.fans.count, Set(targets.map(\.fanID)).count == targets.count,
              Set(targets.map(\.fanID)) == Set(snapshot.fans.map(\.id)) else { throw ControlError.invalidFan }
        let safety = current.required.isEmpty ? 0 : try observeChipGuard(snapshot, now: now).enforcedPercent
        var safe: [FanTarget] = []
        for target in targets {
            guard let fan = snapshot.fans.first(where: { $0.id == target.fanID }), target.rpm.isFinite,
                  target.rpm >= fan.minimumRPM, target.rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
            if current.required.isEmpty {
                guard target.rpm == fan.maximumRPM else { throw ControlError.invalidFan }
            }
            safe.append(FanTarget(target.fanID, max(target.rpm, try fan.rpm(percent: safety))))
        }
        current.renewedAt = now; lease = current
        return safe
    }
    public func expired(at now: Double) -> Bool { lease.map { !now.isFinite || now < $0.renewedAt || now - $0.renewedAt >= timeout || ($0.expiresAt.map { now >= $0 || !$0.isFinite } ?? false) } ?? false }
    /// Recheck after returning from any potentially blocking hardware adapter.
    public func requireLiveLease(at now: Double) throws {
        guard lease != nil, !restoring, !expired(at: now) else { throw ControlError.staleSession }
    }
    public mutating func disconnect(owner: UUID) -> Bool { guard lease?.owner == owner else { return false }; revoke(); return true }
}
public struct MessageRateLimiter: Sendable {
    private var tokens: Double = 10
    private var lastTime: Double?
    public init() {}
    public mutating func allow(at now: Double) -> Bool {
        guard now.isFinite, lastTime.map({ now >= $0 }) ?? true else { return false }
        if let lastTime { tokens = min(10, tokens + (now - lastTime) * 4) }
        lastTime = now
        guard tokens >= 1 else { return false }; tokens -= 1; return true
    }
}
public enum PeerRequirement {
    /// Team and identifier are pinned; command-line arguments never select the trust policy.
    public static func make(team: String, identifier: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
        guard team.count == 10, team.unicodeScalars.allSatisfy({ allowed.contains($0) }), !identifier.isEmpty,
              identifier.count <= 128, identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw ControlError.unauthorized }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(identifier)\""
    }
}
public enum Wire {
    public static let version = 2
    public static let maxBytes = 16_384
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maxBytes else { throw ControlError.malformedMessage }
        do { return try JSONDecoder().decode(type, from: data) } catch { throw ControlError.malformedMessage }
    }
    /// Commands have a closed shape. Responses retain additive-field compatibility.
    public static func decodeCommand<T: HelperCommand>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == T.fields else { throw ControlError.malformedMessage }
        return try decode(type, from: data)
    }
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value); guard data.count <= maxBytes else { throw ControlError.malformedMessage }; return data
    }
}
public protocol HelperCommand: Decodable { static var fields: Set<String> { get } }
public struct LeaseRequest: Codable, Sendable, HelperCommand {
    public static let fields: Set<String> = ["version", "generation", "required"]
    public var version: Int
    public var generation: UInt64
    public var required: Set<SensorRole>
    public init(generation: UInt64, required: Set<SensorRole>) {
        version = Wire.version; self.generation = generation; self.required = required
    }
}
public struct TargetRequest: Codable, Sendable, HelperCommand {
    public static let fields: Set<String> = ["version", "leaseID", "generation", "snapshotID", "targets"]
    public var version: Int; public var leaseID: UUID; public var generation: UInt64; public var snapshotID: UUID; public var targets: [FanTarget]
    public init(leaseID: UUID, generation: UInt64, snapshotID: UUID, targets: [FanTarget]) { version = Wire.version; self.leaseID = leaseID; self.generation = generation; self.snapshotID = snapshotID; self.targets = targets }
}
public struct HelperStatus: Codable, Sendable {
    public var chipGuard: ChipGuardReading? = nil
    public var helperBuild: String?
    public var version: Int = Wire.version
    public var automaticVerified: Bool
    public var manualQualified: Bool
    public var observationOnly: Bool
    public var snapshot: HardwareSnapshot?
    public var fault: String?
    public var capabilities: HardwareCapabilities?
    public var restoration: RestorationReport?
    public var startupRestoration: RestorationReport?
    public var recovery: RecoveryTrialStatus?
    public var recoveryBlocker: String?
    public init(automaticVerified: Bool, manualQualified: Bool = false, observationOnly: Bool = false, snapshot: HardwareSnapshot? = nil, fault: String? = nil, capabilities: HardwareCapabilities? = nil, restoration: RestorationReport? = nil, startupRestoration: RestorationReport? = nil) { self.startupRestoration = startupRestoration; self.capabilities = capabilities; self.restoration = restoration; self.automaticVerified = automaticVerified; self.manualQualified = manualQualified; self.observationOnly = observationOnly; self.snapshot = snapshot; self.fault = fault }
}
@objc public protocol FanHelperXPC {
    func status(withReply reply: @escaping (Data?, String?) -> Void)
    func beginLease(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func applyTargets(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func restoreAutomatic(withReply reply: @escaping (Bool, String?) -> Void)
    func qualifyRecovery(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void)
}
public protocol PrivilegedFanClient: FanController {
    func status() async throws -> HelperStatus
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) async throws
}
