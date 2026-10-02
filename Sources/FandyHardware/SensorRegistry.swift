import Foundation
import FandyCore
public enum SensorReduction: String, Codable, Sendable { case average, maximum }
public struct SensorMapping: Sendable {
    public var role: SensorRole
    public var keys: [String]
    public var reduction: SensorReduction
    public init(role: SensorRole, keys: [String], reduction: SensorReduction = .average) {
        self.role = role; self.keys = keys; self.reduction = reduction
    }
    /// Every reviewed member is mandatory; incomplete groups never become partial averages.
    public func reading(sequence: UInt64, qualified: Bool, now: Double,
                        read: (String) throws -> DiscoveredSensor) -> SensorReading {
        var values: [Double] = [], earliest = now
        guard !keys.isEmpty, Set(keys).count == keys.count else {
            return SensorReading(role, nil, at: now, sequence: sequence, health: .corrupt)
        }
        for key in keys {
            guard let sample = try? read(key), sample.key == key, sample.error == nil,
                  sample.type == "flt ", sample.size == 4, sample.bytes.count == 4,
                  let value = sample.value, value.isFinite, value > 0, value < 150,
                  let completed = sample.sampledAt, completed.isFinite, completed >= now else {
                return SensorReading(role, nil, at: now, sequence: sequence, health: .missing)
            }
            earliest = values.isEmpty ? completed : min(earliest, completed)
            values.append(value)
        }
        let value = reduction == .maximum ? values.max()! : values.reduce(0, +) / Double(values.count)
        return SensorReading(role, value, at: earliest, sequence: sequence, health: qualified ? .valid : .unverified)
    }
}
public enum SensorRegistry {
    public static let model = "Mac17,9"
    // Observed physical topology for this model; these are not RPM or manual-state defaults.
    public static let observedFanIDs = [0, 1]
    public static let observedModeKeys = [0: "F0md", 1: "F1md"]
    // Complete published M5 GPU domain. Tg1g was absent from the enumerated Mac17,9
    // catalogs, including the 2026-10-01 automatic-mode recording; not excluded by core count.
    public static let publishedGPUKeys = ["Tg0U","Tg0X","Tg0d","Tg0g","Tg0j","Tg1Y","Tg1c","Tg1g"]
    // Explicit read-only candidate manifest from the Mac17,9 catalog. Never a runtime prefix rule.
    // Both Tp and Tm responded during the separate CPU pulse. Physical membership still needs review,
    // so this wider informational envelope cannot enter a temperature-control lease.
    public static let cpuRegionCandidates = ["Tm00","Tm04","Tm08","Tm0C","Tm0G","Tm0K","Tm0O","Tm0R","Tm0U","Tm0X","Tm0a","Tm0d","Tm0g","Tm0j","Tm0m","Tm0p","Tm0u","Tm0y","Tm1E","Tm1I","Tm1M","Tm1Q","Tm1U","Tm1Y","Tm1c","Tm1g","Tm1k","Tm1o","Tm1s","Tm1x","Tm21","Tm25","Tm29","Tm2D","Tm2H","Tm2L","Tm2P","Tm2T","Tm2j","Tm2n","Tp00","Tp04","Tp08","Tp0C","Tp0G","Tp0K","Tp0O","Tp0R","Tp0U","Tp0X","Tp0a","Tp0d","Tp0g","Tp0j","Tp0m","Tp0p","Tp0u","Tp0y","Tp1E","Tp1I","Tp1Q","Tp1U","Tp1g"]
    /// Candidates were observed read-only. TG Pro corroboration is still required.
    public static let mappings: [SensorMapping] = [
        SensorMapping(role: .cpuAverage, keys: cpuRegionCandidates),
        SensorMapping(role: .gpuAverage, keys: ["Tg0U","Tg0X","Tg0d","Tg0g","Tg0j","Tg1Y","Tg1c"]),
        SensorMapping(role: .trackpad, keys: ["Ts0P"]),
        SensorMapping(role: .actuator, keys: ["Ts1P"]),
        SensorMapping(role: .airflowLeft, keys: ["TaLP"]),
        SensorMapping(role: .airflowTop, keys: ["TaTP"]),
        SensorMapping(role: .airflowRight, keys: ["TaRF"]),
        SensorMapping(role: .charger, keys: ["TCHP"]),
        SensorMapping(role: .powerSupply, keys: ["TPSP"]),
        SensorMapping(role: .wireless, keys: ["TW0P"])
    ].flatMap { mapping in
        if mapping.role == .cpuAverage || mapping.role == .gpuAverage {
            return [mapping, SensorMapping(role: mapping.role == .cpuAverage ? .cpuPeak : .gpuPeak,
                                           keys: mapping.keys, reduction: .maximum)]
        }
        return [mapping]
    }
    // Reviewed from independent published names, 1156 contemporaneous reference pairs,
    // competing-candidate analysis and the separate chassis temperature response.
    // Top ambient/airflow semantics and chip coverage remain pending; this grants no curve lease.
    public static let reviewedComfortRoles: Set<SensorRole> = [.trackpad, .actuator, .airflowLeft, .airflowRight]
    // Automatic handback passed on both fans on 2026-10-01: manual->0, three
    // idempotent requests and 60 seconds independently observed. See HARDWARE_GATES.
    // Evidence and authority are compiled into the signed build; no preference/XPC bypass exists.
    public static let capabilities = HardwareCapabilities(model: model, stage: .maximumControl, sensors: mappings.map { mapping in
        let source: String = switch mapping.role {
        case .cpuAverage, .cpuPeak: "Stats Tp anchors; Mac17,9 thermal Tp/Tm labels; typed candidate manifest and CPU pulse; earlier TG Pro recordings"
        case .gpuAverage, .gpuPeak: "Stats M5 table; contemporaneous TG Pro recordings"
        case .airflowLeft, .airflowRight, .wireless: "Stats names; contemporaneous TG Pro recordings"
        case .trackpad, .actuator, .charger: "Historical VirtualSMC names; TG Pro recordings"
        case .airflowTop: "iSMC Apple Ambient Top Proximity candidate; TG Pro Airflow Top recordings"
        case .powerSupply: "iSMC Power Supply Proximity candidate; TG Pro recordings"
        default: "Contemporaneous TG Pro recordings"
        }
        let limitation = [SensorRole.cpuAverage, .cpuPeak, .gpuAverage, .gpuPeak].contains(mapping.role)
            ? "Individual identities, aggregation and peak coverage remain unproved on Mac17,9."
            : "Historical or broad-platform names plus rounded reference agreement need Mac17,9 identity review."
        let reviewed = reviewedComfortRoles.contains(mapping.role)
        return SensorEvidence(role: mapping.role, keys: mapping.keys, state: reviewed ? .verified : .pending,
                              source: source + (reviewed ? "; Mac17,9 composite review 2026-10-01, TEMPERATURE_PROFILE_STATUS" : ""),
                              limitation: reviewed ? "Operational comfort mapping; not an independently measured physical surface temperature." : limitation)
    }, topology: .verified, automaticRestoration: .verified, manualTransaction: .verified)
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
        let started = ProcessInfo.processInfo.systemUptime
        // Cache each key once per acquisition; averages and maxima can have independent groups.
        var samples: [String: DiscoveredSensor] = [:]
        for key in Set(SensorRegistry.mappings.flatMap(\.keys)).sorted() {
            samples[key] = try? reader.read(key)
        }
        let sensors = SensorRegistry.mappings.map { mapping in
            mapping.reading(sequence: sequence, qualified: SensorRegistry.capabilities.verifiedRoles.contains(mapping.role),
                            now: started, read: { key in
                guard let sample = samples[key] else { throw HardwareError.invalidMetadata }; return sample
            })
        }
        let pressure: ThermalPressure = switch ProcessInfo.processInfo.thermalState { case .nominal: .nominal; case .fair: .fair; case .serious: .serious; case .critical: .critical; @unknown default: .unknown }
        let fans = try reader.fans()
        guard Set(fans.map(\.id)) == Set(SensorRegistry.observedFanIDs) else { throw ControlError.invalidFan }
        for fan in fans {
            guard let key = SensorRegistry.observedModeKeys[fan.id] else { throw ControlError.invalidFan }
            let mode = try reader.read(key)
            guard mode.type == "ui8 ", mode.size == 1, mode.value == Double(fan.mode.rawValue) else { throw ControlError.invalidFan }
        }
        return HardwareSnapshot(at: ProcessInfo.processInfo.systemUptime, sensors: sensors, fans: fans, pressure: pressure)
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
