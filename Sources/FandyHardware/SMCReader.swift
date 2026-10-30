import Foundation
import CSMC
import FandyCore

public struct DiscoveredSensor: Codable, Sendable, Equatable {
    public var key: String
    public var type: String
    public var size: Int
    public var attributes: UInt8
    public var bytes: [UInt8]
    public var value: Double?
    public var error: String?
    /// Monotonic completion time; absent in older discovery recordings.
    public var sampledAt: Double? = nil
    public init(key: String, type: String, size: Int, attributes: UInt8, bytes: [UInt8],
                value: Double?, error: String?, sampledAt: Double? = nil) {
        self.key = key; self.type = type; self.size = size; self.attributes = attributes
        self.bytes = bytes; self.value = value; self.error = error; self.sampledAt = sampledAt
    }
}
public enum SMCDecoder {
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        let result: Double?
        switch (type, bytes.count) {
        case ("flt ",4), ("flt",4):
            let raw = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            result = Double(Float(bitPattern: raw))
        case ("ui8 ",1): result = Double(bytes[0])
        case ("ui16",2): result = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case ("ui32",4): result = Double(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        case ("sp78",2): result = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case ("fpe2",2): result = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case ("ioft",8):
            // Published 48.16 interpretation; discovery only until a mapping/type is qualified.
            let raw = bytes.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
            result = Double(raw) / 65_536
        default: result = nil
        }
        return result.flatMap { $0.isFinite ? $0 : nil }
    }
}
public final class SMCReader: @unchecked Sendable {
    private let transport: any SMCStructTransport
    private let clock: () -> Double
    private let lock = NSRecursiveLock()
    private struct Metadata { let type: String; let size: Int; let attributes: UInt8 }
    private var metadata: [String: Metadata] = [:]
    public convenience init() throws { self.init(transport: try NativeSMCTransport()) }
    public init(transport: any SMCStructTransport, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.transport = transport; self.clock = clock
    }
    public func transact(_ request: [UInt8]) throws -> SMCStructResponse {
        lock.lock(); defer { lock.unlock() }
        return try transport.transact(request)
    }
    private func request(key: String, command: UInt8) -> [UInt8] {
        var input = [UInt8](repeating: 0, count: 80)
        let number = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        for index in 0..<4 { input[index] = UInt8(truncatingIfNeeded: number >> (index * 8)) }
        input[42] = command; return input
    }
    private func response(_ input: [UInt8], key: String?, operation: String) throws -> [UInt8] {
        let output = try transact(input)
        guard output.count == 80, output.bytes.count == 80 else { throw HardwareError.invalidMetadata }
        guard output.bytes[40] == 0 else { throw SMCReadFailure(operation: operation, key: key, result: output.bytes[40], status: output.bytes[41]) }
        return output.bytes
    }
    public func read(_ key: String) throws -> DiscoveredSensor {
        guard key.utf8.count == 4, key.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 }) else { throw HardwareError.invalidKey }
        lock.lock(); defer { lock.unlock() }
        do {
            let info: Metadata
            // Fan metadata is always re-read. Only temperature metadata is cached;
            // values and completion timestamps are acquired on every sample.
            if key.hasPrefix("T"), let cached = metadata[key] { info = cached }
            else {
                let output = try response(request(key: key, command: 9), key: key, operation: "read_info")
                let size = (0..<4).reduce(UInt32(0)) { $0 | UInt32(output[28 + $1]) << ($1 * 8) }
                guard (1...32).contains(size), let type = String(bytes: output[32..<36].reversed(), encoding: .ascii) else { throw HardwareError.invalidMetadata }
                info = Metadata(type: type, size: Int(size), attributes: output[36])
            }
            var input = request(key: key, command: 5)
            for index in 0..<4 { input[28 + index] = UInt8(truncatingIfNeeded: UInt32(info.size) >> (index * 8)) }
            let output = try response(input, key: key, operation: "read_value")
            let bytes = Array(output[48..<(48 + info.size)])
            if key.hasPrefix("T") { metadata[key] = SMCDecoder.decode(type: info.type, bytes: bytes) == nil ? nil : info }
            return DiscoveredSensor(key: key, type: info.type, size: info.size, attributes: info.attributes, bytes: bytes,
                value: SMCDecoder.decode(type: info.type, bytes: bytes), error: nil, sampledAt: clock())
        } catch { metadata[key] = nil; throw error }
    }
    public func enumerate(prefix: String? = nil) throws -> [DiscoveredSensor] {
        let count = try read("#KEY")
        guard let value = count.value, value >= 1, value <= 20_000, value.rounded() == value else { throw HardwareError.invalidMetadata }
        var items: [DiscoveredSensor] = []
        for index in 0..<UInt32(value) {
            var input = [UInt8](repeating: 0, count: 80); input[42] = 8
            for offset in 0..<4 { input[44 + offset] = UInt8(truncatingIfNeeded: index >> (offset * 8)) }
            let output = try response(input, key: nil, operation: "enumerate")
            guard let key = String(bytes: output[0..<4].reversed(), encoding: .ascii) else { throw HardwareError.invalidMetadata }
            if let prefix, !key.hasPrefix(prefix) { continue }
            do { items.append(try read(key)) }
            catch { items.append(DiscoveredSensor(key: key, type: "unknown", size: 0, attributes: 0, bytes: [], value: nil, error: "read_failed")) }
        }
        return items
    }
    public func fanModeKey(_ id: Int) throws -> String { try fanModeReading(id).key }
    private func fanModeReading(_ id: Int) throws -> DiscoveredSensor {
        guard (0..<8).contains(id) else { throw ControlError.invalidFan }
        let names = ["F\(id)md", "F\(id)Md"]
        for key in names {
            do {
                let reading = try read(key)
                guard reading.type == "ui8 ", reading.size == 1 else { throw HardwareError.invalidMetadata }
                return reading
            } catch where HardwareError.isMissingKey(error) { continue }
        }
        throw HardwareError.invalidMetadata
    }
    public func fans() throws -> [Fan] {
        let count = try read("FNum")
        guard count.type == "ui8 ", let number = count.value, (0...8).contains(number), number.rounded() == number else { throw HardwareError.invalidMetadata }
        return try (0..<Int(number)).map { id in
            func rpm(_ suffix: String) throws -> Double {
                let reading = try read("F\(id)\(suffix)")
                guard (reading.type == "flt " && reading.size == 4 || reading.type == "fpe2" && reading.size == 2), let value = reading.value else { throw HardwareError.invalidMetadata }
                return value
            }
            let mode = try fanModeReading(id)
            guard let decodedMode = SMCDecoder.fanMode(type: mode.type, bytes: mode.bytes) else { throw HardwareError.invalidMetadata }
            let fan = Fan(id: id, min: try rpm("Mn"), max: try rpm("Mx"), actual: try rpm("Ac"), target: try rpm("Tg"), mode: decodedMode)
            try fan.validate(); return fan
        }
    }
}
public enum HardwareError: Error, LocalizedError {
    public static func isMissingKey(_ error: any Error) -> Bool {
        if let failure = error as? SMCReadFailure { return failure.failure.code == 0x84 }
        if case HardwareError.smc(let code) = error { return UInt32(bitPattern: code) == 0xFAD00084 }
        return false
    }
    case smc(Int32), invalidKey, invalidMetadata
    public var errorDescription: String? {
        switch self { case .smc(let code): "SMC read failed: \(String(UInt32(bitPattern: code), radix: 16))"; case .invalidKey: "Invalid SMC identifier"; case .invalidMetadata: "Unsupported or unreliable SMC metadata" }
    }
}

public extension SMCDecoder {
    static func fanMode(type: String, bytes: [UInt8]) -> FanMode? {
        guard type == "ui8 ", bytes.count == 1, let mode = FanMode(rawValue: Int(bytes[0])), mode != .unknown else { return nil }
        return mode
    }
}
