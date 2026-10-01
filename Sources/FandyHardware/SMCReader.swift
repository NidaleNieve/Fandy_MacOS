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
    private let handle: OpaquePointer
    private let lock = NSLock()
    public init() throws {
        var error: Int32 = 0
        guard let connection = fandy_smc_open(&error) else { throw HardwareError.smc(error) }
        handle = connection
    }
    deinit { fandy_smc_close(handle) }
    public func read(_ key: String) throws -> DiscoveredSensor {
        guard key.utf8.count == 4, key.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 }) else { throw HardwareError.invalidKey }
        lock.lock(); defer { lock.unlock() }
        var raw = FandySMCValue()
        let result = key.withCString { fandy_smc_read(handle, $0, &raw) }
        guard result == 0 else { throw HardwareError.smc(result) }
        let type = withUnsafeBytes(of: raw.type) { String(bytes: $0.prefix(4), encoding: .ascii) ?? "????" }
        let bytes = withUnsafeBytes(of: raw.bytes) { Array($0.prefix(Int(raw.size))) }
        return DiscoveredSensor(key: key, type: type, size: Int(raw.size), attributes: raw.attributes, bytes: bytes, value: SMCDecoder.decode(type: type, bytes: bytes), error: nil)
    }
    public func enumerate(prefix: String? = nil) throws -> [DiscoveredSensor] {
        let count = try read("#KEY")
        guard let value = count.value, value >= 1, value <= 20_000, value.rounded() == value else { throw HardwareError.invalidMetadata }
        var items: [DiscoveredSensor] = []
        for index in 0..<UInt32(value) {
            var name = [CChar](repeating: 0, count: 5)
            lock.lock(); let result = fandy_smc_key_at(handle, index, &name); lock.unlock()
            guard result == 0 else { throw HardwareError.smc(result) }
            let key = String(bytes: name.prefix(4).map { UInt8(bitPattern: $0) }, encoding: .ascii) ?? ""
            if let prefix, !key.hasPrefix(prefix) { continue }
            do { items.append(try read(key)) }
            catch { items.append(DiscoveredSensor(key: key, type: "unknown", size: 0, attributes: 0, bytes: [], value: nil, error: error.localizedDescription)) }
        }
        return items
    }
    public func fanModeKey(_ id: Int) throws -> String {
        guard (0..<8).contains(id) else { throw ControlError.invalidFan }
        let names = ["F\(id)md", "F\(id)Md"]
        for key in names { if let reading = try? read(key), reading.type == "ui8 ", reading.size == 1 { return key } }
        throw HardwareError.invalidMetadata
    }
    public func fans() throws -> [Fan] {
        let count = try read("FNum")
        guard count.type == "ui8 ", let number = count.value, (1...8).contains(number), number.rounded() == number else { throw HardwareError.invalidMetadata }
        return try (0..<Int(number)).map { id in
            func rpm(_ suffix: String) throws -> Double {
                let reading = try read("F\(id)\(suffix)")
                guard reading.type == "flt ", reading.size == 4, let value = reading.value else { throw HardwareError.invalidMetadata }
                return value
            }
            let mode = try read(fanModeKey(id))
            guard let decodedMode = SMCDecoder.fanMode(type: mode.type, bytes: mode.bytes) else { throw HardwareError.invalidMetadata }
            let fan = Fan(id: id, min: try rpm("Mn"), max: try rpm("Mx"), actual: try rpm("Ac"), target: try rpm("Tg"), mode: decodedMode)
            try fan.validate(); return fan
        }
    }
}
public enum HardwareError: Error, LocalizedError {
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
