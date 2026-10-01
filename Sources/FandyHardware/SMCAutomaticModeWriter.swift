import Foundation
import FandyCore

public struct SMCStructResponse: Sendable {
    public let bytes: [UInt8]
    public let count: Int
    public init(bytes: [UInt8], count: Int) { self.bytes = bytes; self.count = count }
}
public protocol SMCStructTransport { func transact(_ request: [UInt8]) throws -> SMCStructResponse }
/// Restoration-only codec. No manual modes, RPM encoding, arbitrary keys or target clearing.
/// The actual transport exists only in the helper and enforces its compiled authority and root UID.
public enum SMCAutomaticModeWriter {
    public static func restore(fanID: Int, metadata: DiscoveredSensor, transport: any SMCStructTransport) throws {
        guard (0..<8).contains(fanID), metadata.key == "F\(fanID)md", metadata.error == nil,
              metadata.type == "ui8 ", metadata.size == 1, metadata.attributes == 208,
              let mode = SMCDecoder.fanMode(type: metadata.type, bytes: metadata.bytes),
              mode == .automatic || mode == .manual else { throw HardwareError.invalidMetadata }
        // Attribute byte 208 and modes 0/1 are the reviewed Mac17,9 metadata signature.
        // No claim about undocumented attribute bits or firmware mode 3 is required.
        var input = [UInt8](repeating: 0, count: 80)
        let key = metadata.key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        for index in 0..<4 { input[index] = UInt8(truncatingIfNeeded: key >> (index * 8)) }
        input[28] = 1 // uint32 data size, little endian
        input[42] = 6 // byte-addressed SMC write command; selector 2 lives in the transport
        input[48] = 0 // automatic only
        let response = try transport.transact(input)
        guard response.count == 80, response.bytes.count == 80, response.bytes[40] == 0 else { throw ControlError.restorationUnverified }
    }
}
