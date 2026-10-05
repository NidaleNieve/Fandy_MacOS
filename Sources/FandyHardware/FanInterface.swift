import Foundation
import FandyCore

public enum FanRPMFormat: String, Sendable { case float = "flt ", fixed = "fpe2" }
public struct FanInterface: Sendable {
    public let fanIDs: [Int]
    public let modeKeys: [Int: String]
    public let targetFormats: [Int: FanRPMFormat]
    public let forceTestAvailable: Bool
    public let locallyTested: Bool
    public var supportsTargets: Bool { targetFormats.count == fanIDs.count }
    public static func discover(identity: DeviceIdentity, read: (String) throws -> DiscoveredSensor) throws -> Self {
        guard identity.supportedNotebook else { throw ControlError.hardwareUnqualified }
        let count = try read("FNum")
        guard count.key == "FNum", count.type == "ui8 ", count.size == 1, count.bytes.count == 1,
              count.error == nil, count.value == Double(count.bytes[0]), (1...2).contains(count.bytes[0]) else { throw HardwareError.invalidMetadata }
        let ids = Array(0..<Int(count.bytes[0])), local = identity.model == SensorRegistry.model
        guard !local || ids == SensorRegistry.observedFanIDs else { throw HardwareError.invalidMetadata }
        var keys: [Int: String] = [:], formats: [Int: FanRPMFormat] = [:]
        for id in ids {
            var matches: [DiscoveredSensor] = []
            for key in ["F\(id)md", "F\(id)Md"] {
                do { matches.append(try read(key)) }
                catch HardwareError.smc(let code) where UInt32(bitPattern: code) == 0xFAD00084 { }
                catch { throw error }
            }
            guard matches.count == 1, let metadata = matches.first else { throw HardwareError.invalidMetadata }
            try validateMode(metadata, id: id, locallyTested: local)
            keys[id] = metadata.key
            if let target = try? read("F\(id)Tg"), let format = FanRPMFormat(rawValue: target.type),
               (try? validateTarget(target, id: id, format: format, locallyTested: local)) != nil { formats[id] = format }
        }
        // Absence is specifically the SMC not-found result. A corrupt/unreadable
        // global handover flag must not be silently treated as a direct interface.
        var forceTest = false
        do {
            let flag = try read("Ftst")
            guard !local else { throw HardwareError.invalidMetadata }
            try validateFlag(flag); forceTest = true
        } catch HardwareError.smc(let code) where UInt32(bitPattern: code) == 0xFAD00084 {
            forceTest = false
        } catch {
            throw error
        }
        guard forceTest || keys.values.allSatisfy({ key in (try? read(key).value) != 3 }) else { throw HardwareError.invalidMetadata }
        return Self(fanIDs: ids, modeKeys: keys, targetFormats: formats, forceTestAvailable: forceTest, locallyTested: local)
    }
    public func validateMode(_ metadata: DiscoveredSensor, id: Int) throws {
        guard modeKeys[id] == metadata.key else { throw HardwareError.invalidMetadata }
        try Self.validateMode(metadata, id: id, locallyTested: locallyTested)
    }
    public func validateTarget(_ metadata: DiscoveredSensor, id: Int) throws {
        guard let format = targetFormats[id] else { throw HardwareError.invalidMetadata }
        try Self.validateTarget(metadata, id: id, format: format, locallyTested: locallyTested)
    }
    private static func writable(_ sample: DiscoveredSensor) -> Bool {
        // Public interoperability references describe read/write permission bits.
        // Other attribute bits are retained and compared on the write connection.
        sample.attributes & 0xC0 == 0xC0 && sample.error == nil
    }
    private static func validateMode(_ sample: DiscoveredSensor, id: Int, locallyTested: Bool) throws {
        guard ["F\(id)md", "F\(id)Md"].contains(sample.key), sample.type == "ui8 ", sample.size == 1,
              sample.bytes.count == 1, let mode = SMCDecoder.fanMode(type: sample.type, bytes: sample.bytes),
              sample.value == Double(mode.rawValue), writable(sample),
              !locallyTested || (sample.key == "F\(id)md" && sample.attributes == 208 && mode != .system) else { throw HardwareError.invalidMetadata }
    }
    private static func validateTarget(_ sample: DiscoveredSensor, id: Int, format: FanRPMFormat, locallyTested: Bool) throws {
        guard sample.key == "F\(id)Tg", sample.type == format.rawValue,
              sample.size == (format == .float ? 4 : 2), sample.bytes.count == sample.size, writable(sample),
              let value = sample.value, value >= 0, value <= 30_000,
              value == SMCDecoder.decode(type: sample.type, bytes: sample.bytes),
              !locallyTested || (format == .float && sample.attributes == 212) else { throw HardwareError.invalidMetadata }
    }
    public static func validateFlag(_ sample: DiscoveredSensor) throws {
        guard sample.key == "Ftst", sample.type == "ui8 ", sample.size == 1, sample.bytes.count == 1,
              sample.bytes[0] <= 1, sample.value == Double(sample.bytes[0]), writable(sample) else { throw HardwareError.invalidMetadata }
    }
    public func restoreMode(id: Int, metadata: DiscoveredSensor, transport: any SMCStructTransport) throws {
        try validateMode(metadata, id: id)
        if locallyTested { try SMCAutomaticModeWriter.restore(fanID: id, metadata: metadata, transport: transport) }
        else if metadata.value != 3 {
            try SMCRecoveryWriter.write(key: metadata.key, type: metadata.type, attributes: metadata.attributes, bytes: [0], transport: transport)
        }
        // Firmware's protected System state is already non-manual. Global Ftst release
        // and independent final mode readback remain mandatory in FanRestoration.
    }
    public func startManual(id: Int, metadata: DiscoveredSensor, transport: any SMCStructTransport) throws {
        try validateMode(metadata, id: id)
        guard metadata.value == 0 else { throw ControlError.restorationUnverified }
        try SMCRecoveryWriter.write(key: metadata.key, type: metadata.type, attributes: metadata.attributes, bytes: [1], transport: transport)
    }
    public func writeTarget(_ target: FanTarget, fan: Fan, metadata: DiscoveredSensor, transport: any SMCStructTransport) throws {
        try fan.validate(); try validateTarget(metadata, id: fan.id)
        guard target.fanID == fan.id, fan.mode == .manual, target.rpm.isFinite, target.rpm > 0,
              target.rpm >= fan.minimumRPM, target.rpm <= fan.maximumRPM, metadata.value == fan.targetRPM else { throw ControlError.invalidFan }
        let bytes: [UInt8]
        switch targetFormats[fan.id] {
        case .float:
            let value = Float(target.rpm)
            guard value.isFinite, Double(value) >= target.rpm, Double(value) <= fan.maximumRPM else { throw ControlError.invalidFan }
            bytes = (0..<4).map { UInt8(truncatingIfNeeded: value.bitPattern >> ($0 * 8)) }
        case .fixed:
            guard target.rpm <= 16_383.75 else { throw ControlError.invalidFan }
            let value = UInt16(ceil(target.rpm * 4)); bytes = [UInt8(value >> 8), UInt8(truncatingIfNeeded: value)]
        case nil: throw HardwareError.invalidMetadata
        }
        try SMCRecoveryWriter.write(key: metadata.key, type: metadata.type, attributes: metadata.attributes, bytes: bytes, transport: transport)
    }
    public func writeForceTest(_ enabled: Bool, metadata: DiscoveredSensor, transport: any SMCStructTransport) throws {
        guard forceTestAvailable, !locallyTested else { throw ControlError.hardwareUnqualified }
        try Self.validateFlag(metadata)
        try SMCRecoveryWriter.write(key: "Ftst", type: "ui8 ", attributes: metadata.attributes, bytes: [enabled ? 1 : 0], transport: transport)
    }
}

/// Cancellation arrives from the XPC ingress thread even while handover is waiting.
/// The hardware queue remains the sole writer; cancellation only revokes admission.
public final class HardwareOperationFence: @unchecked Sendable {
    public struct Token: Sendable, Equatable {
        fileprivate let generation: UUID
        fileprivate let owner: UUID?
        fileprivate let ownerGeneration: UUID?
    }
    private let lock = NSLock()
    private var generation = UUID()
    private var owners: [UUID: UUID] = [:]
    public init() {}
    /// Mirrors the helper's bounded connection admission; tokens never register peers.
    public func connect(owner: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard owners.count < 8, owners[owner] == nil else { return false }
        owners[owner] = UUID(); return true
    }
    public func token() -> Token {
        lock.lock(); defer { lock.unlock() }
        return Token(generation: generation, owner: nil, ownerGeneration: nil)
    }
    public func token(owner: UUID) throws -> Token {
        lock.lock(); defer { lock.unlock() }
        guard let epoch = owners[owner] else { throw ControlError.staleSession }
        return Token(generation: generation, owner: owner, ownerGeneration: epoch)
    }
    /// System restoration and power transitions revoke all admitted work.
    public func cancel() { lock.lock(); defer { lock.unlock() }; generation = UUID() }
    public func cancel(owner: UUID) {
        lock.lock(); defer { lock.unlock() }
        if owners[owner] != nil { owners[owner] = UUID() }
    }
    public func disconnected(owner: UUID) {
        lock.lock(); defer { lock.unlock() }
        owners.removeValue(forKey: owner)
    }
    public func require(_ token: Token) throws {
        lock.lock(); defer { lock.unlock() }
        guard token.generation == generation else { throw ControlError.staleSession }
        if let owner = token.owner {
            guard owners[owner] == token.ownerGeneration else { throw ControlError.staleSession }
        }
    }
}

/// Bounded handover polling, independent of transport and wall time in tests.
public enum FanHandover {
    /// An accepted automatic-mode write may remain manual briefly in readback.
    /// Wait for acknowledgement without issuing another command or accepting
    /// unknown ownership; the caller still attempts every fan on failure.
    public static func awaitRelease(deadline: Double, clock: () -> Double,
        read: () throws -> FanMode, pause: () -> Void) throws {
        guard deadline.isFinite else { throw ControlError.invalidNumber }
        while true {
            let now = clock()
            guard now.isFinite, now < deadline else { throw ControlError.staleSession }
            switch try read() {
            case .automatic, .system: return
            case .manual: pause()
            default: throw ControlError.restorationUnverified
            }
        }
    }
    public static func awaitAutomatic(ids: [Int], deadline: Double, clock: () -> Double,
        cancelled: () throws -> Void, read: (Int) throws -> FanMode, pause: () -> Void) throws {
        var pending = Set(ids)
        guard !pending.isEmpty, pending.count == ids.count, deadline.isFinite else { throw ControlError.invalidFan }
        while !pending.isEmpty {
            try cancelled()
            guard clock().isFinite, clock() < deadline else { throw ControlError.staleSession }
            for id in pending.sorted() {
                switch try read(id) {
                case .automatic: pending.remove(id)
                case .system: break
                default: throw ControlError.restorationUnverified
                }
            }
            if !pending.isEmpty { pause() }
        }
        try cancelled()
        guard clock() < deadline else { throw ControlError.staleSession }
    }
}
