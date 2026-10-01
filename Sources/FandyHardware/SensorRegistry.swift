import Foundation
import FandyCore
public struct SensorMapping: Sendable {
    public var role: SensorRole
    public var keys: [String]
}
public enum SensorRegistry {
    public static let model = "Mac17,9"
    // Observed physical topology for this model; these are not RPM or manual-state defaults.
    public static let observedFanIDs = [0, 1]
    public static let observedModeKeys = [0: "F0md", 1: "F1md"]
    // Complete published M5 GPU domain. Tg1g was absent from the enumerated Mac17,9
    // catalogs, including the 2026-10-01 automatic-mode recording; not excluded by core count.
    public static let publishedGPUKeys = ["Tg0U","Tg0X","Tg0d","Tg0g","Tg0j","Tg1Y","Tg1c","Tg1g"]
    /// Candidates were observed read-only. TG Pro corroboration is still required.
    public static let mappings = [
        SensorMapping(role: .cpuAverage, keys: ["Tp00","Tp04","Tp08","Tp0C","Tp0G","Tp0K","Tp0O","Tp0R","Tp0U","Tp0X","Tp0a","Tp0d","Tp0g","Tp0j","Tp0m","Tp0p","Tp0u","Tp0y"]),
        SensorMapping(role: .gpuAverage, keys: ["Tg0U","Tg0X","Tg0d","Tg0g","Tg0j","Tg1Y","Tg1c"]),
        SensorMapping(role: .trackpad, keys: ["Ts0P"]),
        SensorMapping(role: .actuator, keys: ["Ts1P"]),
        SensorMapping(role: .airflowLeft, keys: ["TaLP"]),
        SensorMapping(role: .airflowTop, keys: ["TaTP"]),
        SensorMapping(role: .airflowRight, keys: ["TaRF"]),
        SensorMapping(role: .charger, keys: ["TCHP"]),
        SensorMapping(role: .powerSupply, keys: ["TPSP"]),
        SensorMapping(role: .wireless, keys: ["TW0P"])
    ]
    // Automatic handback passed on both fans on 2026-10-01: manual->0, three
    // idempotent requests and 60 seconds independently observed. See HARDWARE_GATES.
    // Evidence and authority are compiled into the signed build; no preference/XPC bypass exists.
    public static let capabilities = HardwareCapabilities(model: model, stage: .recoveryQualification, sensors: mappings.flatMap { mapping in
        let source: String = switch mapping.role {
        case .cpuAverage, .gpuAverage: "Stats M5 table; contemporaneous TG Pro recordings"
        case .airflowLeft, .airflowRight, .wireless: "Stats names; contemporaneous TG Pro recordings"
        case .trackpad, .actuator, .charger: "Historical VirtualSMC names; TG Pro recordings"
        case .airflowTop: "iSMC Apple Ambient Top Proximity candidate; TG Pro Airflow Top recordings"
        case .powerSupply: "iSMC Power Supply Proximity candidate; TG Pro recordings"
        default: "Contemporaneous TG Pro recordings"
        }
        let limitation = mapping.role == .cpuAverage || mapping.role == .gpuAverage
            ? "Individual identities, aggregation and peak coverage remain unproved on Mac17,9."
            : "Historical or broad-platform names plus rounded reference agreement need Mac17,9 identity review."
        let roles: [SensorRole] = mapping.role == .cpuAverage ? [.cpuAverage, .cpuPeak]
            : mapping.role == .gpuAverage ? [.gpuAverage, .gpuPeak] : [mapping.role]
        return roles.map { SensorEvidence(role: $0, keys: mapping.keys, source: source, limitation: limitation) }
    }, topology: .verified, automaticRestoration: .verified)
}
public final class HardwareSnapshotReader: @unchecked Sendable {
    private let lock = NSLock()
    private let reader: SMCReader
    private var sequence: UInt64 = 0
    public init() throws { reader = try SMCReader() }
    public func snapshot() throws -> HardwareSnapshot {
        lock.lock(); defer { lock.unlock() }
        guard Self.machineModel() == SensorRegistry.model else { throw ControlError.hardwareUnqualified }
        sequence += 1
        let now = ProcessInfo.processInfo.systemUptime
        var sensors: [SensorReading] = []
        for mapping in SensorRegistry.mappings {
            let samples = mapping.keys.map { try? reader.read($0) }
            let valid = samples.compactMap { sample -> Double? in
                guard let sample, sample.type == "flt ", sample.size == 4, sample.bytes.count == 4, let value = sample.value, value > 0, value < 150 else { return nil }; return value
            }
            let complete = valid.count == mapping.keys.count
            let health: ReadingHealth = !complete ? .missing : SensorRegistry.capabilities.verifiedRoles.contains(mapping.role) ? .valid : .unverified
            let value = complete ? valid.reduce(0,+) / Double(valid.count) : nil
            sensors.append(SensorReading(mapping.role, value, at: now, sequence: sequence, health: health))
            if mapping.role == .cpuAverage || mapping.role == .gpuAverage {
                let peakRole: SensorRole = mapping.role == .cpuAverage ? .cpuPeak : .gpuPeak
                let peakHealth: ReadingHealth = !complete ? .missing : SensorRegistry.capabilities.verifiedRoles.contains(peakRole) ? .valid : .unverified
                sensors.append(SensorReading(peakRole, complete ? valid.max() : nil, at: now, sequence: sequence, health: peakHealth))
            }
        }
        let pressure: ThermalPressure = switch ProcessInfo.processInfo.thermalState { case .nominal: .nominal; case .fair: .fair; case .serious: .serious; case .critical: .critical; @unknown default: .unknown }
        let fans = try reader.fans()
        guard Set(fans.map(\.id)) == Set(SensorRegistry.observedFanIDs) else { throw ControlError.invalidFan }
        for fan in fans {
            guard let key = SensorRegistry.observedModeKeys[fan.id] else { throw ControlError.invalidFan }
            let mode = try reader.read(key)
            guard mode.type == "ui8 ", mode.size == 1, mode.value == Double(fan.mode.rawValue) else { throw ControlError.invalidFan }
        }
        return HardwareSnapshot(at: now, sensors: sensors, fans: fans, pressure: pressure)
    }
}

public extension HardwareSnapshotReader {
    static func machineModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size < 256 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
public actor AppleSiliconSensorProvider: TemperatureSensorProvider {
    private let reader: HardwareSnapshotReader
    public init() throws { reader = try HardwareSnapshotReader() }
    public func snapshot() throws -> HardwareSnapshot { try reader.snapshot() }
}
