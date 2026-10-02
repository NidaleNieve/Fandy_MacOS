import Foundation

public enum HardwareStage: String, Codable, Sendable {
    case observation, restorationQualification, recoveryQualification, manualQualification, maximumControl, curveQualification, qualifiedControl
}
public enum QualificationState: String, Codable, Sendable { case pending, verified }
public struct SensorEvidence: Codable, Sendable, Equatable {
    public let role: SensorRole
    public let keys: [String]
    public let state: QualificationState
    public let source: String
    public let limitation: String
    public init(role: SensorRole, keys: [String], state: QualificationState = .pending, source: String, limitation: String) {
        self.role = role; self.keys = keys; self.state = state; self.source = source; self.limitation = limitation
    }
}
/// Constructed by the signed build, never loaded from preferences or accepted as an XPC command.
/// A received helper capability report cannot grant authority to the local client.
public struct HardwareCapabilities: Codable, Sendable, Equatable {
    public let model: String
    public let stage: HardwareStage
    public let sensors: [SensorEvidence]
    public let topology: QualificationState
    public let automaticRestoration: QualificationState
    public let manualTransaction: QualificationState
    public let chipControl: ChipControlPolicy?
    public var chipPolicy: ChipControlPolicy { chipControl ?? .cpuGPU }
    public init(model: String, stage: HardwareStage = .observation, sensors: [SensorEvidence] = [], topology: QualificationState = .pending,
                automaticRestoration: QualificationState = .pending, manualTransaction: QualificationState = .pending, chipControl: ChipControlPolicy? = nil) {
        self.model = model; self.stage = stage; self.sensors = sensors; self.topology = topology
        self.automaticRestoration = automaticRestoration; self.manualTransaction = manualTransaction
        self.chipControl = chipControl
    }
    public static let requiredRoles = Set([SensorRole.cpuAverage, .gpuAverage, .cpuPeak, .gpuPeak, .trackpad, .actuator,
                                           .airflowLeft, .airflowTop, .airflowRight, .charger, .powerSupply, .wireless])
    public var verifiedRoles: Set<SensorRole> {
        Set(sensors.filter { evidence in
            evidence.state == .verified && !evidence.keys.isEmpty && !evidence.source.isEmpty &&
            evidence.keys.allSatisfy { $0.utf8.count == 4 && $0.utf8.allSatisfy { (32...126).contains($0) } } &&
            sensors.filter { $0.role == evidence.role }.count == 1
        }.map(\.role))
    }
    public var allSensorsVerified: Bool { Self.requiredRoles.isSubset(of: verifiedRoles) }
    // Release authority is independent of temperature health and identity. The user-approved
    // restoration-first stage cannot enter manual mode, even with fully qualified sensors.
    public var canRestore: Bool { stage != .observation && topology == .verified }
    public var canControl: Bool {
        [.maximumControl, .curveQualification, .qualifiedControl].contains(stage) && canRestore && automaticRestoration == .verified && manualTransaction == .verified
    }
    public func permits(_ profile: Profile) -> Bool {
        guard canControl else { return false }
        if profile.kind == .maximum { return true }
        return stage == .qualifiedControl && profile.requiredSensors(chipPolicy: chipPolicy).isSubset(of: verifiedRoles)
    }
    public func permits(required: Set<SensorRole>) -> Bool {
        canControl && (required.isEmpty || ([.curveQualification, .qualifiedControl].contains(stage) && chipPolicy.required.isSubset(of: required) && required.isSubset(of: verifiedRoles)))
    }
    public var canQualifyCurves: Bool { stage == .curveQualification && canControl && chipPolicy.required.isSubset(of: verifiedRoles) }
    /// Separate, signed-build authority for bounded qualification; never admits profile leases.
    /// The current restoration build cannot obtain it through preferences or XPC data.
    public var canQualifyManual: Bool {
        stage == .manualQualification && canRestore && allSensorsVerified && automaticRestoration == .verified
    }
    /// User-authorized mechanical recovery trials before sensor identity qualification.
    /// No ordinary leases, curve control or caller-selected fan commands are admitted.
    public var canQualifyRecovery: Bool {
        stage == .recoveryQualification && canRestore && automaticRestoration == .verified
    }
    public func forMachine(_ actual: String) -> Self {
        actual == model ? self : Self(model: actual)
    }
    public func reasonUnavailable(_ profile: Profile) -> String {
        let missing = profile.requiredSensors(chipPolicy: chipPolicy).subtracting(verifiedRoles).sorted { $0.rawValue < $1.rawValue }
        if !missing.isEmpty { return "Awaiting sensor verification: " + missing.map(\.name).joined(separator: ", ") }
        if stage == .curveQualification && profile.kind == .custom { return "Variable-speed handback testing is not finished." }
        return blockers.first ?? "This profile is not qualified for this hardware."
    }
    public var blockers: [String] {
        var result: [String] = []
        if stage == .observation { result.append("This build permits monitoring only.") }
        if !allSensorsVerified { result.append("Sensor identities and chip coverage await qualification.") }
        if topology != .verified { result.append("Fan topology awaits restoration qualification.") }
        if automaticRestoration != .verified { result.append("Physical automatic restoration has not passed.") }
        if manualTransaction != .verified { result.append("Physical manual control and recovery have not passed.") }
        return result
    }
}
public enum FanOwnership: String, Sendable {
    case appleObserved, manualObserved, unknown
    public static func observe(_ snapshot: HardwareSnapshot?, now: Double) -> Self {
        guard let snapshot, (try? snapshot.validateFans(now: now)) != nil else { return .unknown }
        guard snapshot.fans.allSatisfy({ $0.mode == .automatic || $0.mode == .manual }) else { return .unknown }
        return snapshot.fans.allSatisfy { $0.mode == .automatic } ? .appleObserved : .manualObserved
    }
}
public enum HelperHealth: String, Sendable { case unavailable, monitoring, controlReady, fault }
public struct ProfileEligibility: Sendable {
    public let allowed: Bool
    public let reason: String?
    public static func evaluate(_ profile: Profile, capabilities: HardwareCapabilities, helper: HelperHealth,
                                snapshot: HardwareSnapshot?, now: Double) -> Self {
        do {
            try profile.validate()
            guard capabilities.permits(profile) else { return Self(allowed: false, reason: capabilities.reasonUnavailable(profile)) }
            guard helper == .controlReady else { throw ControlError.helperUnavailable }
            guard let snapshot else { throw ControlError.invalidSnapshot }
            try snapshot.validate(now: now, required: profile.requiredSensors(chipPolicy: capabilities.chipPolicy))
            return Self(allowed: true, reason: nil)
        } catch { return Self(allowed: false, reason: error.localizedDescription) }
    }
}
