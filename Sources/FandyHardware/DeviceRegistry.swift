import Foundation
import FandyCore

public enum AppleChipFamily: Int, CaseIterable, Sendable { case m1 = 1, m2, m3, m4, m5 }
public struct DeviceIdentity: Sendable {
    public let model: String
    public let chip: String
    public let appleSilicon: Bool
    public init(model: String, chip: String, appleSilicon: Bool) {
        self.model = model; self.chip = chip; self.appleSilicon = appleSilicon
    }
    public var family: AppleChipFamily? {
        guard appleSilicon else { return nil }
        let tokens = chip.split(separator: " ").map(String.init)
        guard tokens.count >= 2, tokens[0] == "Apple", tokens[1].count == 2,
              tokens.count == 2 || (tokens.count == 3 && ["Pro", "Max"].contains(tokens[2])),
              let generation = Int(tokens[1].dropFirst()), tokens[1].first == "M" else { return nil }
        return AppleChipFamily(rawValue: generation)
    }
    public var supportedNotebook: Bool { family == DeviceRegistry.notebookFamilies[model] && family != nil }
    public static var current: Self {
        Self(model: HardwareSnapshotReader.machineModel(), chip: sysctlString("machdep.cpu.brand_string"), appleSilicon: arm64Available())
    }
    private static func sysctlString(_ key: String) -> String {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size < 256 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "unknown"
    }
    private static func arm64Available() -> Bool {
        var value: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
}

public struct ResolvedDevice: Sendable {
    public let identity: DeviceIdentity
    public let capabilities: HardwareCapabilities
    public let mappings: [SensorMapping]
    public let fanInterface: FanInterface?
    public let failure: HelperFailure?
    public init(identity: DeviceIdentity, capabilities: HardwareCapabilities, mappings: [SensorMapping], fanInterface: FanInterface?, failure: HelperFailure? = nil) {
        self.identity = identity; self.capabilities = capabilities; self.mappings = mappings; self.fanInterface = fanInterface; self.failure = failure
    }
    public var acquisitionKeys: [String] { Set(mappings.flatMap(\.keys)).sorted() }
}

/// Signed, source-backed registry. Neither configuration imports nor IPC can add recipes.
public enum DeviceRegistry {
    public static let statsRevision = "9ceb6e3b20001c4102f473c5dc3e96b388a77da9"
    // Apple Support 108052, reviewed 2026-10-04. Chip identity is checked separately.
    public static let notebookFamilies: [String: AppleChipFamily] = {
        let families: [(AppleChipFamily, [String])] = [
            (.m1, ["MacBookPro17,1", "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4"]),
            (.m2, ["Mac14,7", "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10"]),
            (.m3, ["Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11"]),
            (.m4, ["Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8"]),
            (.m5, ["Mac17,2", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9"])
        ]
        return Dictionary(uniqueKeysWithValues: families.flatMap { family, models in models.map { ($0, family) } })
    }()
    public static func canInstallHelper(identity: DeviceIdentity) -> Bool { identity.appleSilicon }
    public static func declaredCapabilities(identity: DeviceIdentity) -> HardwareCapabilities {
        HardwareCapabilities(model: identity.model, chipControl: identity.model == SensorRegistry.model ? .conservativeEnvelope : .cpuGPU)
    }
    public static var current: ResolvedDevice {
        let identity = DeviceIdentity.current
        guard let reader = try? SMCReader() else {
            return ResolvedDevice(identity: identity, capabilities: HardwareCapabilities(model: identity.model), mappings: [], fanInterface: nil)
        }
        return resolve(identity: identity, read: { try reader.read($0) })
    }
    public static func candidates(for identity: DeviceIdentity) -> (efficiency: [String], performance: [String], gpu: [String]) {
        switch identity.family {
        case .m1: (ReferenceSensorKeys.m1Efficiency, ReferenceSensorKeys.m1Performance, ReferenceSensorKeys.m1Gpu)
        case .m2: (ReferenceSensorKeys.m2Efficiency, ReferenceSensorKeys.m2Performance, ReferenceSensorKeys.m2Gpu)
        case .m3: (ReferenceSensorKeys.m3Efficiency, ReferenceSensorKeys.m3Performance, ReferenceSensorKeys.m3Gpu)
        case .m4: (ReferenceSensorKeys.m4Efficiency, ReferenceSensorKeys.m4Performance,
                   (identity.chip == "Apple M4" ? ReferenceSensorKeys.m4BaseGPU : ReferenceSensorKeys.m4ProMaxGPU) + ReferenceSensorKeys.m4Gpu)
        case .m5: (ReferenceSensorKeys.m5SuperCores, ReferenceSensorKeys.m5Performance, ReferenceSensorKeys.m5Gpu)
        case nil: ([], [], [])
        }
    }
    public static func resolve(identity: DeviceIdentity, read: (String) throws -> DiscoveredSensor) -> ResolvedDevice {
        resolveSensors(device: resolveFans(identity: identity, read: read), read: read)
    }
    public static func resolveFans(identity: DeviceIdentity, read: (String) throws -> DiscoveredSensor) -> ResolvedDevice {
        var interface: FanInterface?, failure: HelperFailure?
        if identity.supportedNotebook {
            do { interface = try FanInterface.discover(identity: identity, read: read); failure = interface?.targetFailure }
            catch { failure = Self.failure(error, operation: "fan_discovery") }
        } else { failure = .init(kind: .metadata, domain: "Fandy", code: 0, operation: "fan_discovery") }
        let cap = HardwareCapabilities(model: identity.model, stage: interface == nil ? .observation : .restorationQualification,
            topology: interface == nil ? .pending : interface!.locallyTested ? .verified : .referenceSupported,
            automaticRestoration: interface == nil ? .pending : .referenceSupported,
            chipControl: identity.model == SensorRegistry.model ? .conservativeEnvelope : .cpuGPU,
            evidence: interface == nil ? .unsupported : interface!.locallyTested ? .locallyTested : .referenceSupported)
        return .init(identity: identity, capabilities: cap, mappings: [], fanInterface: interface, failure: failure)
    }
    public static func failure(_ error: any Error, operation: String) -> HelperFailure {
        if let e = error as? SMCReadFailure { return e.failure }
        if case HardwareError.smc(let code) = error { return .init(kind: .smc, domain: "IOKit", code: Int(code), operation: operation) }
        return .init(kind: .metadata, domain: "Fandy", code: 0, operation: operation)
    }
    public static func report(device: ResolvedDevice) -> RuntimeDeviceReport {
        .init(model: device.identity.model, chip: device.identity.chip, catalog: statsRevision,
              recipe: device.fanInterface.map { $0.locallyTested ? "m5-direct" : $0.forceTestAvailable ? "reference-force-test" : "reference-direct" })
    }
    public static func validate(report: RuntimeDeviceReport, capabilities: HardwareCapabilities, identity: DeviceIdentity) throws -> HardwareCapabilities {
        guard report.model == identity.model, report.chip == identity.chip, report.catalog == statsRevision,
              capabilities.model == identity.model else { throw ControlError.hardwareUnqualified }
        if capabilities.canRestore {
            guard identity.supportedNotebook, ["m5-direct","reference-force-test","reference-direct"].contains(report.recipe ?? ""),
                  (report.recipe == "m5-direct") == (identity.model == SensorRegistry.model) else { throw ControlError.hardwareUnqualified }
        }
        let groups = candidates(for: identity)
        let chip = Set(groups.efficiency + groups.performance + groups.gpu)
        let allowed = chip.union(["Ts0P","Ts1P","TaLP","TaTP","TaRF","TCHP","TPSP","TW0P"])
            .union(identity.model == SensorRegistry.model ? SensorRegistry.chipEnvelopeKeys : [])
        for sensor in capabilities.sensors {
            guard !sensor.keys.isEmpty, Set(sensor.keys).isSubset(of: allowed),
                  sensor.state != .verified || identity.model == SensorRegistry.model,
                  identity.model == SensorRegistry.model || ![.socPeak,.cpuRegion,.gpuRegion].contains(sensor.role) else { throw ControlError.hardwareUnqualified }
            let expected: Set<String>
            switch sensor.role {
            case .cpuAverage,.cpuPeak: expected = Set(groups.efficiency + groups.performance)
            case .gpuAverage,.gpuPeak: expected = Set(groups.gpu)
            case .trackpad: expected = ["Ts0P"]
            case .actuator: expected = ["Ts1P"]
            case .airflowLeft: expected = ["TaLP"]
            case .airflowTop: expected = ["TaTP"]
            case .airflowRight: expected = ["TaRF"]
            case .charger: expected = ["TCHP"]
            case .powerSupply: expected = ["TPSP"]
            case .wireless: expected = ["TW0P"]
            default: expected = allowed
            }
            if identity.model == SensorRegistry.model {
                guard let mapping = SensorRegistry.mappings.first(where: { $0.role == sensor.role }),
                      Set(sensor.keys) == Set(mapping.keys), sensor.keys.count == mapping.keys.count else { throw ControlError.hardwareUnqualified }
            } else {
                guard Set(sensor.keys).isSubset(of: expected), Set(sensor.keys).count == sensor.keys.count else { throw ControlError.hardwareUnqualified }
                if sensor.state.supported && [.cpuAverage,.cpuPeak].contains(sensor.role) {
                    guard !Set(sensor.keys).isDisjoint(with: groups.efficiency), !Set(sensor.keys).isDisjoint(with: groups.performance) else { throw ControlError.hardwareUnqualified }
                }
            }
        }
        guard capabilities.chipPolicy == declaredCapabilities(identity: identity).chipPolicy else { throw ControlError.hardwareUnqualified }
        return capabilities
    }
    public static func resolveSensors(device: ResolvedDevice, read: (String) throws -> DiscoveredSensor) -> ResolvedDevice {
        let identity = device.identity, interface = device.fanInterface
        if identity.model == SensorRegistry.model && identity.supportedNotebook {
            var cap = interface == nil ? HardwareCapabilities(model: identity.model, sensors: SensorRegistry.capabilities.sensors,
                chipControl: .conservativeEnvelope) : SensorRegistry.capabilities
            if let interface, !interface.supportsTargets {
                cap = HardwareCapabilities(model: identity.model, stage: .restorationQualification,
                    sensors: SensorRegistry.capabilities.sensors, topology: .verified,
                    automaticRestoration: .verified, manualTransaction: .pending,
                    chipControl: .conservativeEnvelope, evidence: .locallyTested)
            }
            return ResolvedDevice(identity: identity, capabilities: cap, mappings: SensorRegistry.mappings, fanInterface: interface, failure: device.failure)
        }
        let groups = candidates(for: identity)
        // Probe only published candidates, once. An absent variant member may be excluded
        // at resolution; a selected member that later fails invalidates the entire group.
        var samples: [String: DiscoveredSensor] = [:], invalidKeys: Set<String> = []
        let comfort: [(SensorRole, String)] = [(.trackpad,"Ts0P"),(.actuator,"Ts1P"),(.airflowLeft,"TaLP"),
            (.airflowTop,"TaTP"),(.airflowRight,"TaRF"),(.charger,"TCHP"),(.powerSupply,"TPSP"),(.wireless,"TW0P")]
        for key in Set(groups.efficiency + groups.performance + groups.gpu + comfort.map(\.1)) {
            do {
                let sample = try read(key); samples[key] = sample
                if sample.key != key || !SensorMapping.usableTemperature(sample) { invalidKeys.insert(key) }
            } catch where HardwareError.isMissingKey(error) {
                // Source-table members absent on a variant are explicit startup omissions.
            } catch { invalidKeys.insert(key) }
        }
        func present(_ keys: [String]) -> [String] { keys.filter { samples[$0].map(SensorMapping.usableTemperature) == true } }
        let efficiency = present(groups.efficiency), performance = present(groups.performance), gpu = present(groups.gpu)
        let cpu = efficiency + performance
        var mappings: [SensorMapping] = []
        func mapping(_ role: SensorRole, _ keys: [String], _ reduction: SensorReduction = .average) {
            guard !keys.isEmpty else { return }
            mappings.append(SensorMapping(role: role, keys: keys, reduction: reduction,
                types: Dictionary(uniqueKeysWithValues: keys.map { ($0, samples[$0]!.type) })))
        }
        mapping(.cpuAverage, cpu); mapping(.cpuPeak, cpu, .maximum)
        mapping(.gpuAverage, gpu); mapping(.gpuPeak, gpu, .maximum)
        for (role, key) in comfort where samples[key].map(SensorMapping.usableTemperature) == true { mapping(role, [key]) }
        let chipSupported = !efficiency.isEmpty && !performance.isEmpty && !gpu.isEmpty &&
            invalidKeys.isDisjoint(with: Set(groups.efficiency + groups.performance + groups.gpu))
        let supportedComfort: Set<SensorRole> = [.trackpad,.actuator,.airflowLeft,.airflowTop,.airflowRight,.wireless]
        let evidence = mappings.map { mapping in
            let eligible = identity.supportedNotebook && ((SensorRole.safety.contains(mapping.role) || [.cpuAverage,.gpuAverage].contains(mapping.role)) ? chipSupported : supportedComfort.contains(mapping.role))
            return SensorEvidence(role: mapping.role, keys: mapping.keys, state: eligible ? .referenceSupported : .pending,
                source: "Stats " + statsRevision + "; historical VirtualSMC names; iSMC ambient-top descriptor fact; typed startup observations",
                limitation: "Reference-supported region membership; not physically tested by Fandy on this model.",
                displayName: mapping.role == .airflowTop ? "Top proximity" : nil)
        }
        let cap = HardwareCapabilities(model: identity.model, stage: interface == nil ? .observation : interface?.supportsTargets == true ? .qualifiedControl : .restorationQualification,
            sensors: evidence, topology: interface == nil ? .pending : .referenceSupported,
            automaticRestoration: interface == nil ? .pending : .referenceSupported,
            manualTransaction: interface?.supportsTargets == true ? .referenceSupported : .pending, chipControl: .cpuGPU,
            evidence: interface == nil ? .unsupported : .referenceSupported)
        return ResolvedDevice(identity: identity, capabilities: cap, mappings: mappings, fanInterface: interface, failure: device.failure)
    }
}
