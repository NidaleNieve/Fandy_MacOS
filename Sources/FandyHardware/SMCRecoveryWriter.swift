import Foundation
import FandyCore

/// Exact observed Mac17,9 command codec. The root transport and trial deadline live
/// exclusively in the helper. No user-selected key, mode or RPM is exposed over XPC.
public enum SMCRecoveryWriter {
    public static func prepare(target: FanTarget, fan: Fan, metadata: DiscoveredSensor, transport: any SMCStructTransport) throws {
        try fan.validate()
        guard [0, 1].contains(fan.id), target.fanID == fan.id, fan.mode == .automatic,
              target.rpm.isFinite, target.rpm > fan.actualRPM,
              target.rpm >= fan.minimumRPM, target.rpm <= fan.maximumRPM,
              metadata.key == "F\(fan.id)Tg", metadata.type == "flt ", metadata.size == 4,
              metadata.attributes == 212, metadata.bytes.count == 4, metadata.error == nil,
              let previous = SMCDecoder.decode(type: metadata.type, bytes: metadata.bytes),
              previous == metadata.value, previous >= 0, previous <= 30_000 else { throw HardwareError.invalidMetadata }
        let encoded = Float(target.rpm)
        guard encoded.isFinite, Double(encoded) >= fan.minimumRPM, Double(encoded) <= fan.maximumRPM,
              Double(encoded) > fan.actualRPM else { throw ControlError.invalidFan }
        let bytes = (0..<4).map { UInt8(truncatingIfNeeded: encoded.bitPattern >> ($0 * 8)) }
        try write(key: metadata.key, type: metadata.type, attributes: metadata.attributes, bytes: bytes, transport: transport)
    }
    public static func activate(target: FanTarget, mode: DiscoveredSensor, prepared: DiscoveredSensor, transport: any SMCStructTransport) throws {
        guard [0, 1].contains(target.fanID), mode.key == "F\(target.fanID)md",
              mode.type == "ui8 ", mode.size == 1, mode.attributes == 208, mode.bytes == [0], mode.error == nil,
              prepared.key == "F\(target.fanID)Tg", prepared.type == "flt ", prepared.size == 4,
              prepared.attributes == 212, prepared.bytes.count == 4, prepared.error == nil,
              target.rpm.isFinite, target.rpm > 0,
              let observed = SMCDecoder.decode(type: prepared.type, bytes: prepared.bytes),
              abs(observed - target.rpm) <= 0.5 else { throw HardwareError.invalidMetadata }
        try write(key: mode.key, type: mode.type, attributes: mode.attributes, bytes: [1], transport: transport)
    }
    /// Reviewed M5 mode-first order, admitted only from an independently observed
    /// stopped/zero-target baseline. No fallback for a spinning or stale-target fan.
    public static func startStopped(target: FanTarget, fan: Fan, mode: DiscoveredSensor,
                                    previous: DiscoveredSensor, transport: any SMCStructTransport) throws {
        try fan.validate()
        guard [0, 1].contains(fan.id), target.fanID == fan.id, fan.mode == .automatic,
              fan.actualRPM == 0, fan.targetRPM == 0, target.rpm == fan.minimumRPM + 200,
              target.rpm.isFinite, target.rpm > 0, target.rpm <= fan.maximumRPM,
              mode.key == "F\(fan.id)md", mode.type == "ui8 ", mode.size == 1,
              mode.attributes == 208, mode.bytes == [0], mode.error == nil,
              previous.key == "F\(fan.id)Tg", previous.type == "flt ", previous.size == 4,
              previous.attributes == 212, previous.bytes.count == 4, previous.error == nil,
              previous.value == 0, SMCDecoder.decode(type: previous.type, bytes: previous.bytes) == 0 else {
            throw HardwareError.invalidMetadata
        }
        try write(key: mode.key, type: mode.type, attributes: mode.attributes, bytes: [1], transport: transport)
    }
    public static func targetStartedStopped(target: FanTarget, fan: Fan, metadata: DiscoveredSensor,
                                            transport: any SMCStructTransport) throws {
        guard fan.mode == .manual, fan.targetRPM == 0, metadata.value == 0,
              target.rpm == fan.minimumRPM + 200 else { throw HardwareError.invalidMetadata }
        // Reuse all target bounds/metadata/representation checks, adapting only the
        // expected mode after the narrowly admitted stopped-fan mode command.
        var validation = fan; validation.mode = .automatic
        try prepare(target: target, fan: validation, metadata: metadata, transport: transport)
    }
    private static func write(key: String, type: String, attributes: UInt8, bytes: [UInt8], transport: any SMCStructTransport) throws {
        var input = [UInt8](repeating: 0, count: 80)
        let number = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        for index in 0..<4 { input[index] = UInt8(truncatingIfNeeded: number >> (index * 8)) }
        // Complete the key-info type field as in the reviewed userspace write ABI.
        // The type comes only from the exact validated fan metadata above.
        let format = type.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        for index in 0..<4 { input[32 + index] = UInt8(truncatingIfNeeded: format >> (index * 8)) }
        // Reference writers query metadata on the writing connection, immediately
        // before the write. Revalidate that response rather than trust the other port.
        input[42] = 9
        let info = try transport.transact(input)
        try validateResponse(info, key: key)
        guard Array(info.bytes[28..<32]) == [UInt8(bytes.count), 0, 0, 0],
              Array(info.bytes[32..<36]) == Array(input[32..<36]), info.bytes[36] == attributes else {
            throw HardwareError.invalidMetadata
        }
        input[28] = UInt8(bytes.count); input[42] = 6
        input.replaceSubrange(48..<(48 + bytes.count), with: bytes)
        let response = try transport.transact(input)
        try validateResponse(response, key: key)
    }
    private static func validateResponse(_ response: SMCStructResponse, key: String) throws {
        guard response.count == 80, response.bytes.count == 80 else { throw RecoveryWriteError.invalidReply(key: key, count: response.count) }
        guard response.bytes[40] == 0 else { throw RecoveryWriteError.rejected(key: key, result: response.bytes[40], status: response.bytes[41]) }
    }
}

public enum RecoveryWriteError: Error, LocalizedError {
    case invalidReply(key: String, count: Int)
    case rejected(key: String, result: UInt8, status: UInt8)
    public var errorDescription: String? {
        switch self {
        case .invalidReply(let key, let count): "Recovery write \(key): invalid response length \(count)"
        case .rejected(let key, let result, let status): "Recovery write \(key): SMC result \(result), status \(status)"
        }
    }
}

/// Bounded observation only: do not reissue a command or accept a different target.
public enum RecoveryTargetReadback {
    public static func awaitTarget(_ target: FanTarget, baseline: Fan, deadline: Double,
                                   clock: () -> Double, read: () throws -> Fan, pause: () -> Void) throws {
        let start = clock(), limit = min(deadline, start + 0.5)
        guard start.isFinite, deadline.isFinite, start < limit else { throw ControlError.staleSession }
        var previous = start
        while true {
            let before = clock()
            guard before.isFinite, before >= previous, before < deadline else { throw ControlError.staleSession }
            let fan = try read(), now = clock()
            try fan.validate()
            guard now.isFinite, now >= before, now >= previous, now < deadline, now <= limit else { throw ControlError.staleSession }
            previous = now
            guard fan.id == target.fanID, fan.mode == .manual,
                  fan.minimumRPM == baseline.minimumRPM, fan.maximumRPM == baseline.maximumRPM,
                  target.rpm.isFinite, target.rpm >= fan.minimumRPM, target.rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
            guard let observed = fan.targetRPM, observed.isFinite else { throw ControlError.invalidFan }
            if abs(observed - target.rpm) <= 0.5 { return }
            guard observed == 0, now < limit else {
                throw RecoveryTrialError.targetMismatch(fanID: fan.id, expected: target.rpm, observed: observed)
            }
            pause()
        }
    }
}
