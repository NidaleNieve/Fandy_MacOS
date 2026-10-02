import Foundation

/// A hardware-build decision, not a profile preference or caller-selected XPC field.
public enum ChipControlPolicy: String, Codable, Sendable {
    case cpuGPU, conservativeEnvelope
    public var required: Set<SensorRole> { self == .cpuGPU ? SensorRole.safety : [.socPeak] }
    public func temperature(in snapshot: HardwareSnapshot, now: Double) throws -> Double {
        try required.map { try snapshot.value($0, now: now) }.max()!
    }
}

public enum SensorRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case cpuAverage, gpuAverage, cpuPeak, gpuPeak, socPeak
    case trackpad, actuator, airflowLeft, airflowTop, airflowRight, charger, powerSupply, wireless
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .cpuAverage: "CPU Average"
        case .gpuAverage: "GPU Average"
        case .cpuPeak: "Hottest CPU"
        case .gpuPeak: "Hottest GPU"
        case .socPeak: "Chip envelope"
        case .trackpad: "Trackpad"
        case .actuator: "Trackpad Actuator"
        case .airflowLeft: "Airflow Left"
        case .airflowTop: "Airflow Top"
        case .airflowRight: "Airflow Right"
        case .charger: "Charger Proximity"
        case .powerSupply: "Power Supply Proximity"
        case .wireless: "Wireless Proximity"
        }
    }
    public static let safety: Set<Self> = [.cpuPeak, .gpuPeak]
    public static let comfort: Set<Self> = [.trackpad, .actuator, .airflowLeft, .airflowTop, .airflowRight]
}
public enum ReadingHealth: String, Codable, Sendable { case valid, missing, stale, corrupt, unverified }
public struct SensorReading: Codable, Sendable, Equatable {
    public var role: SensorRole
    public var celsius: Double?
    public var sampledAt: TimeInterval
    public var sequence: UInt64
    public var health: ReadingHealth
    public init(_ role: SensorRole, _ celsius: Double?, at: TimeInterval, sequence: UInt64 = 0, health: ReadingHealth = .valid) {
        self.role = role; self.celsius = celsius; self.sampledAt = at; self.sequence = sequence; self.health = health
    }
    public func value(now: TimeInterval, maxAge: Double = 3) throws -> Double {
        guard health == .valid, let celsius, celsius.isFinite, celsius > 0, celsius < 150,
              sampledAt.isFinite, now.isFinite, now >= sampledAt, now - sampledAt <= maxAge else {
            throw ControlError.sensorUnavailable(role)
        }
        return celsius
    }
}
public enum FanMode: Int, Codable, Sendable { case automatic = 0, manual = 1, system = 3, unknown = -1 }
public struct Fan: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public var minimumRPM: Double
    public var maximumRPM: Double
    public var actualRPM: Double
    public var targetRPM: Double?
    public var mode: FanMode
    public init(id: Int, min: Double, max: Double, actual: Double, target: Double? = nil, mode: FanMode = .automatic) {
        self.id = id; minimumRPM = min; maximumRPM = max; actualRPM = actual; targetRPM = target; self.mode = mode
    }
    public func validate() throws {
        guard (0..<8).contains(id), minimumRPM.isFinite, maximumRPM.isFinite, minimumRPM >= 0,
              maximumRPM > minimumRPM, maximumRPM <= 30_000, actualRPM.isFinite, actualRPM >= 0,
              actualRPM <= 30_000, mode != .unknown else { throw ControlError.invalidFan }
        if let targetRPM, !targetRPM.isFinite || targetRPM < 0 || targetRPM > 30_000 { throw ControlError.invalidFan }
    }
    public func rpm(percent: Double) throws -> Double {
        try validate()
        guard percent.isFinite else { throw ControlError.invalidNumber }
        return minimumRPM + min(100, max(0, percent)) / 100 * (maximumRPM - minimumRPM)
    }
}
public enum ThermalPressure: String, Codable, Sendable { case nominal, fair, serious, critical, unknown }
public struct HardwareSnapshot: Codable, Sendable, Equatable {
    public var id: UUID
    public var sampledAt: TimeInterval
    public var sensors: [SensorReading]
    public var fans: [Fan]
    public var thermalPressure: ThermalPressure
    public init(at: TimeInterval, sensors: [SensorReading], fans: [Fan], pressure: ThermalPressure = .nominal, id: UUID = UUID()) {
        self.id = id; sampledAt = at; self.sensors = sensors; self.fans = fans; thermalPressure = pressure
    }
    public func value(_ role: SensorRole, now: TimeInterval) throws -> Double {
        let matches = sensors.filter { $0.role == role }
        guard matches.count == 1, let reading = matches.first else { throw ControlError.sensorUnavailable(role) }
        return try reading.value(now: now)
    }
    public func validate(now: TimeInterval, required: Set<SensorRole>) throws {
        try validateFans(now: now)
        for role in required { _ = try value(role, now: now) }
        guard thermalPressure == .nominal || thermalPressure == .fair else { throw ControlError.thermalPressure }
    }
    /// Fan ownership can be observed even when temperature identities are not yet qualified.
    /// This does not make a snapshot eligible for a custom-control lease.
    public func validateFans(now: TimeInterval) throws {
        guard sampledAt.isFinite, now >= sampledAt, now - sampledAt <= 3,
              !fans.isEmpty, fans.count <= 8, Set(fans.map(\.id)).count == fans.count else { throw ControlError.invalidSnapshot }
        try fans.forEach { try $0.validate() }
    }
}
public enum ControlError: Error, Equatable, Sendable, LocalizedError {
    case invalidNumber, invalidFan, invalidSnapshot, invalidCurve(String), invalidProfile(String)
    case sensorUnavailable(SensorRole), thermalPressure, helperUnavailable, restorationUnverified
    case unauthorized, malformedMessage, staleSession, hardwareUnqualified, excessiveMessages
    public var errorDescription: String? {
        switch self {
        case .sensorUnavailable(let role): "Sensor unavailable or unreliable: \(role.name)"
        case .invalidCurve(let reason), .invalidProfile(let reason): reason
        case .hardwareUnqualified: "Real fan control is disabled until hardware safety verification is complete."
        case .restorationUnverified: "Fan control state unknown; automatic restoration could not be verified."
        default: String(describing: self)
        }
    }
}
public protocol TemperatureSensorProvider: Sendable { func snapshot() async throws -> HardwareSnapshot }
public protocol FanController: Sendable {
    func apply(_ targets: [FanTarget], generation: UInt64) async throws
    func restoreAutomatic() async throws
}
public struct FanTarget: Codable, Sendable, Equatable {
    public var fanID: Int
    public var rpm: Double
    public init(_ id: Int, _ rpm: Double) { fanID = id; self.rpm = rpm }
}
public enum CurveInput: String, Codable, CaseIterable, Sendable {
    case chip, trackpad, actuator, airflow
    public var label: String { switch self { case .chip: "Chip"; case .trackpad: "Trackpad"; case .actuator: "Actuator"; case .airflow: "Airflow" } }
    public var required: Set<SensorRole> {
        switch self { case .chip: [.cpuPeak, .gpuPeak]; case .trackpad: [.trackpad]; case .actuator: [.actuator]; case .airflow: [.airflowLeft, .airflowTop, .airflowRight] }
    }
    public func required(chipPolicy: ChipControlPolicy) -> Set<SensorRole> { self == .chip ? chipPolicy.required : required }
}
