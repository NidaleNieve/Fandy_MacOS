import Foundation
import FandyCore
public enum SensorReduction: String, Codable, Sendable { case average, maximum }
public struct SensorMapping: Sendable {
    public var role: SensorRole
    public var keys: [String]
    public var reduction: SensorReduction
    public var types: [String: String]
    public init(role: SensorRole, keys: [String], reduction: SensorReduction = .average, types: [String: String] = [:]) {
        self.role = role; self.keys = keys; self.reduction = reduction
        self.types = types
    }
    public static func usableTemperature(_ sample: DiscoveredSensor) -> Bool {
        guard sample.error == nil, (sample.type == "flt " && sample.size == 4 || sample.type == "sp78" && sample.size == 2),
              sample.bytes.count == sample.size, let value = sample.value,
              SMCDecoder.decode(type: sample.type, bytes: sample.bytes) == value else { return false }
        return value.isFinite && value > 0 && value < 150
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
                  sample.type == (types[key] ?? "flt "),
                  sample.size == (sample.type == "sp78" ? 2 : 4), sample.bytes.count == sample.size,
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
    // Fan IDs observed on Mac17,9.
    public static let observedFanIDs = [0, 1]
    public static let observedModeKeys = [0: "F0md", 1: "F1md"]
    // Tg1g is absent from Mac17,9 catalogs; keep the other published GPU members.
    public static let publishedGPUKeys = ["Tg0U","Tg0X","Tg0d","Tg0g","Tg0j","Tg1Y","Tg1c","Tg1g"]
    // Fixed Mac17,9 CPU-region candidates. Tp/Tm physical identities remain unresolved.
    public static let cpuRegionCandidates = ["Tm00","Tm04","Tm08","Tm0C","Tm0G","Tm0K","Tm0O","Tm0R","Tm0U","Tm0X","Tm0a","Tm0d","Tm0g","Tm0j","Tm0m","Tm0p","Tm0u","Tm0y","Tm1E","Tm1I","Tm1M","Tm1Q","Tm1U","Tm1Y","Tm1c","Tm1g","Tm1k","Tm1o","Tm1s","Tm1x","Tm21","Tm25","Tm29","Tm2D","Tm2H","Tm2L","Tm2P","Tm2T","Tm2j","Tm2n","Tp00","Tp04","Tp08","Tp0C","Tp0G","Tp0K","Tp0O","Tp0R","Tp0U","Tp0X","Tp0a","Tp0d","Tp0g","Tp0j","Tp0m","Tp0p","Tp0u","Tp0y","Tp1E","Tp1I","Tp1Q","Tp1U","Tp1g"]
    // Fixed GPU-region candidates; indices do not identify physical cores.
    public static let gpuRegionCandidates = ["Tg08","Tg0C","Tg0O","Tg0R","Tg0U","Tg0X","Tg0a","Tg0d","Tg0g","Tg0j","Tg12","Tg16","Tg1I","Tg1M","Tg1Q","Tg1U","Tg1Y","Tg1c","Tg1k","Tg1o","Tg1x","Tg29","Tg2D","Tg2P","Tg2T","Tg2X","Tg2b","Tg2f","Tg2j","Tg2n","Tg2r","Tg3B","Tg3F","Tg3R","Tg3V","Tg3Z","Tg3d","Tg3h","Tg3l","Tg3t","Tg3x","Tg43"]
    public static let chipEnvelopeKeys = (cpuRegionCandidates + gpuRegionCandidates).sorted()
    /// Fixed model-specific groups for display and control.
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
    } + [SensorMapping(role: .socPeak, keys: chipEnvelopeKeys, reduction: .maximum),
         SensorMapping(role: .cpuRegion, keys: cpuRegionCandidates, reduction: .maximum),
         SensorMapping(role: .gpuRegion, keys: gpuRegionCandidates, reduction: .maximum)]
    // Chassis inputs use published names and paired Mac17,9 observations.
    // TaTP is an ambient-top proximity proxy, not TG Pro's exact Airflow Top identity.
    public static let reviewedComfortRoles: Set<SensorRole> = [.trackpad, .actuator, .airflowLeft, .airflowTop, .airflowRight]
    // Mac17,9 control capabilities are compiled from the tested model policy.
    public static let capabilities = HardwareCapabilities(model: model, stage: .qualifiedControl, sensors: mappings.map { mapping in
        let source: String = switch mapping.role {
        case .cpuAverage, .cpuPeak: "Stats Tp anchors; Mac17,9 thermal Tp/Tm labels; typed candidate manifest and CPU pulse; earlier TG Pro recordings"
        case .gpuAverage, .gpuPeak: "Stats M5 table; contemporaneous TG Pro recordings"
        case .socPeak: "Mac17,9 typed catalog, full Tp/Tm/Tg region manifest; published chip anchors and bounded response recordings"
        case .cpuRegion, .gpuRegion: "Subset of the reviewed complete Mac17,9 operational envelope; fixed region manifest and bounded response recordings"
        case .airflowLeft, .airflowRight, .wireless: "Stats names; contemporaneous TG Pro recordings"
        case .trackpad, .actuator, .charger: "Historical VirtualSMC names; TG Pro recordings"
        case .airflowTop: "iSMC Apple Ambient Top Proximity; complete Mac17,9 flt4 observations; 1156 paired readings across 18C and slow chassis response"
        case .powerSupply: "iSMC Power Supply Proximity candidate; TG Pro recordings"
        }
        let limitation: String = switch mapping.role {
        case .airflowTop: "Ambient-top proximity proxy. Exact TG Pro Airflow Top identity is unverified; TRDd/TRDc are competing candidates."
        case .socPeak: "Chip envelope includes Tm regions with unresolved physical identity."
        case .cpuRegion, .gpuRegion: "Regional control input; full chip-envelope validation remains mandatory. Physical core identity and CPU/GPU coverage remain unverified."
        case .cpuAverage, .cpuPeak, .gpuAverage, .gpuPeak: "Physical identities, aggregation and peak coverage remain unverified on Mac17,9."
        default: "Published names and rounded reference readings do not establish Mac17,9 physical identity."
        }
        let reviewed = reviewedComfortRoles.contains(mapping.role) || [.socPeak, .cpuRegion, .gpuRegion].contains(mapping.role)
        return SensorEvidence(role: mapping.role, keys: mapping.keys, state: reviewed ? .verified : .pending,
                              source: source + (reviewed ? "; Mac17,9 sensor policy; docs/COMPATIBILITY.md" : ""),
                              limitation: mapping.role == .airflowTop ? limitation : reviewedComfortRoles.contains(mapping.role) ? "Chassis control input; physical surface temperature is not independently verified." : limitation,
                              displayName: mapping.role == .airflowTop ? "Top proximity" : nil)
    }, topology: .verified, automaticRestoration: .verified, manualTransaction: .verified, chipControl: .conservativeEnvelope)
}
public final class HardwareSnapshotReader: @unchecked Sendable {
    // Immutable membership: every acquisition still reads every required key.
    public let device: ResolvedDevice
    private let lock = NSLock()
    private let reader: SMCReader
    private let verifiedRoles: Set<SensorRole>
    private var sequence: UInt64 = 0
    private let clock: () -> Double
    public init(device: ResolvedDevice? = nil, reader: SMCReader? = nil, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) throws {
        let session = try reader ?? SMCReader()
        self.reader = session; self.clock = clock
        let resolved = device ?? DeviceRegistry.resolve(identity: .current, read: session.read)
        self.device = resolved; self.verifiedRoles = resolved.capabilities.verifiedRoles
    }
    public func snapshot() throws -> HardwareSnapshot {
        try BackgroundWorkMetrics.shared.measure(.sampling) { try autoreleasepool { try acquireSnapshot() } }
    }
    private func acquireSnapshot() throws -> HardwareSnapshot {
        lock.lock(); defer { lock.unlock() }
        sequence += 1
        let started = clock()
        // Cache each key once per acquisition; averages and maxima can have independent groups.
        var samples: [String: DiscoveredSensor] = [:]
        for key in device.acquisitionKeys {
            samples[key] = try? reader.read(key)
        }
        let sensors = device.mappings.map { mapping in
            mapping.reading(sequence: sequence, qualified: verifiedRoles.contains(mapping.role),
                            now: started, read: { key in
                guard let sample = samples[key] else { throw HardwareError.invalidMetadata }; return sample
            })
        }
        let pressure: ThermalPressure = switch ProcessInfo.processInfo.thermalState { case .nominal: .nominal; case .fair: .fair; case .serious: .serious; case .critical: .critical; @unknown default: .unknown }
        // Monitoring survives unavailable/unsupported fan metadata. Empty fans cannot
        // pass validateFans or obtain a lease; temperatures remain independently useful.
        var fans = (try? reader.fans()) ?? []
        if fans.contains(where: { $0.mode == .system }) && device.fanInterface?.forceTestAvailable != true {
            fans = [] // Protected mode 3 is supported only by a reviewed legacy recipe.
        }
        var handover: Bool?
        if device.fanInterface?.forceTestAvailable == true || (device.identity.family != .m5 && device.identity.supportedNotebook) {
            do {
                let flag = try reader.read("Ftst"); try FanInterface.validateFlag(flag)
                handover = flag.value == 1
            } catch where HardwareError.isMissingKey(error) && device.fanInterface?.forceTestAvailable != true {
                handover = false
            } catch { fans = [] } // Unknown global ownership cannot claim automatic control.
        }
        var snapshot = HardwareSnapshot(at: clock(), sensors: sensors, fans: fans, pressure: pressure)
        snapshot.fanHandoverActive = handover
        return snapshot
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
