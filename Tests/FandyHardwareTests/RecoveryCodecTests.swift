import Foundation
import Testing
import FandyCore
@testable import FandyHardware

private final class RecoveryTransport: SMCStructTransport {
    var commands: [[UInt8]] = []
    var requests: [[UInt8]] = []
    var mismatchedInfo = false
    var response = SMCStructResponse(bytes: [UInt8](repeating: 0, count: 80), count: 80)
    func transact(_ request: [UInt8]) throws -> SMCStructResponse {
        requests.append(request)
        if request[42] == 9, response.bytes.count == 80, response.count == 80, response.bytes[40] == 0 {
            var bytes = response.bytes
            let target = request[0] == 0x67
            bytes[28] = target ? 4 : 1
            bytes.replaceSubrange(32..<36, with: request[32..<36])
            bytes[36] = mismatchedInfo ? 0 : target ? 212 : 208
            return SMCStructResponse(bytes: bytes, count: 80)
        }
        if request[42] == 6 { commands.append(request) }
        return response
    }
}
private func targetMetadata(_ rpm: Float = 0) -> DiscoveredSensor {
    let bytes = (0..<4).map { UInt8(truncatingIfNeeded: rpm.bitPattern >> ($0 * 8)) }
    return DiscoveredSensor(key: "F0Tg", type: "flt ", size: 4, attributes: 212, bytes: bytes, value: Double(rpm), error: nil)
}
private func automaticMetadata() -> DiscoveredSensor {
    DiscoveredSensor(key: "F0md", type: "ui8 ", size: 1, attributes: 208, bytes: [0], value: 0, error: nil)
}
@Test func recoveryTargetAndManualCommandsMatchObservedABI() throws {
    let io = RecoveryTransport(), target = FanTarget(0, 2517)
    try SMCRecoveryWriter.prepare(target: target, fan: Fan(id: 0, min: 2317, max: 7826, actual: 0), metadata: targetMetadata(), transport: io)
    try SMCRecoveryWriter.activate(target: target, mode: automaticMetadata(), prepared: targetMetadata(2517), transport: io)
    #expect(io.requests.map { $0[42] } == [9, 6, 9, 6])
    #expect(io.commands.count == 2)
    #expect(Array(io.commands[0][0..<4]) == [0x67, 0x54, 0x30, 0x46])
    #expect(Array(io.commands[0][32..<36]) == [0x20, 0x74, 0x6c, 0x66])
    #expect(Array(io.commands[0][28..<32]) == [4, 0, 0, 0]); #expect(io.commands[0][42] == 6)
    #expect(SMCDecoder.decode(type: "flt ", bytes: Array(io.commands[0][48..<52])) == 2517)
    #expect(Array(io.commands[1][0..<4]) == [0x64, 0x6d, 0x30, 0x46])
    #expect(Array(io.commands[1][32..<36]) == [0x20, 0x38, 0x69, 0x75])
    #expect(io.commands[1][28] == 1); #expect(io.commands[1][42] == 6); #expect(io.commands[1][48] == 1)
}
@Test func recoveryCodecRejectsUnsafeTargetsAndUnreviewedMetadataWithoutWriting() {
    let io = RecoveryTransport(), fan = Fan(id: 0, min: 2317, max: 7826, actual: 2400)
    for rpm in [Double.nan, .infinity, 2400, 2000, 7827] {
        #expect(throws: (any Error).self) { try SMCRecoveryWriter.prepare(target: FanTarget(0, rpm), fan: fan, metadata: targetMetadata(), transport: io) }
    }
    var attribute = targetMetadata(); attribute.attributes = 208
    var key = targetMetadata(); key.key = "F1Tg"
    var type = targetMetadata(); type.type = "ui32"
    for metadata in [attribute, key, type, targetMetadata(.nan)] {
        #expect(throws: (any Error).self) { try SMCRecoveryWriter.prepare(target: FanTarget(0, 2600), fan: fan, metadata: metadata, transport: io) }
    }
    #expect(io.commands.isEmpty)
}
@Test func recoveryManualCodecRequiresPreloadedTargetAndAutomaticMode() {
    let io = RecoveryTransport(), target = FanTarget(0, 2517)
    var unknown = automaticMetadata(); unknown.bytes = [3]
    var alreadyManual = automaticMetadata(); alreadyManual.bytes = [1]
    for mode in [unknown, alreadyManual] {
        #expect(throws: (any Error).self) { try SMCRecoveryWriter.activate(target: target, mode: mode, prepared: targetMetadata(2517), transport: io) }
    }
    #expect(throws: (any Error).self) { try SMCRecoveryWriter.activate(target: target, mode: automaticMetadata(), prepared: targetMetadata(0), transport: io) }
    #expect(io.commands.isEmpty)
}
@Test func recoveryCodecRejectsPartialOrSMCErrorResponses() {
    let io = RecoveryTransport(); var bad = [UInt8](repeating: 0, count: 80); bad[40] = 1
    for response in [SMCStructResponse(bytes: bad, count: 80), SMCStructResponse(bytes: [], count: 80), SMCStructResponse(bytes: bad, count: 79)] {
        io.response = response
        #expect(throws: (any Error).self) {
            try SMCRecoveryWriter.prepare(target: FanTarget(0, 2517), fan: Fan(id: 0, min: 2317, max: 7826, actual: 0), metadata: targetMetadata(), transport: io)
        }
    }
}

@Test func stoppedRecoveryCodecRequiresExactBaselineAndWritesModeThenBoundedTarget() throws {
    let io = RecoveryTransport(), target = FanTarget(0, 2517)
    var fan = Fan(id: 0, min: 2317, max: 7826, actual: 0, target: 0)
    try SMCRecoveryWriter.startStopped(target: target, fan: fan, mode: automaticMetadata(), previous: targetMetadata(), transport: io)
    fan.mode = .manual
    try SMCRecoveryWriter.targetStartedStopped(target: target, fan: fan, metadata: targetMetadata(), transport: io)
    #expect(io.requests.map { $0[42] } == [9, 6, 9, 6])
    #expect(io.commands.count == 2)
    #expect(io.commands[0][48] == 1)
    #expect(Array(io.commands[0][0..<4]) == [0x64, 0x6d, 0x30, 0x46])
    #expect(SMCDecoder.decode(type: "flt ", bytes: Array(io.commands[1][48..<52])) == 2517)
}
@Test func stoppedRecoveryCodecRejectsSpinningNonzeroStaleAndWrongTargetBaselines() {
    let io = RecoveryTransport(), target = FanTarget(0, 2517)
    for fan in [Fan(id: 0, min: 2317, max: 7826, actual: 1, target: 0),
                Fan(id: 0, min: 2317, max: 7826, actual: 0, target: 2500),
                Fan(id: 0, min: 2317, max: 7826, actual: 0, target: 0, mode: .manual)] {
        #expect(throws: (any Error).self) { try SMCRecoveryWriter.startStopped(target: target, fan: fan, mode: automaticMetadata(), previous: targetMetadata(), transport: io) }
    }
    let stopped = Fan(id: 0, min: 2317, max: 7826, actual: 0, target: 0)
    #expect(throws: (any Error).self) { try SMCRecoveryWriter.startStopped(target: FanTarget(0, 2518), fan: stopped, mode: automaticMetadata(), previous: targetMetadata(), transport: io) }
    #expect(throws: (any Error).self) { try SMCRecoveryWriter.startStopped(target: target, fan: stopped, mode: automaticMetadata(), previous: targetMetadata(2517), transport: io) }
    #expect(io.commands.isEmpty)
}

@Test func recoveryWriterRequiresSameConnectionMetadataBeforeAnyWrite() {
    let io = RecoveryTransport(); io.mismatchedInfo = true
    #expect(throws: HardwareError.self) {
        try SMCRecoveryWriter.prepare(target: FanTarget(0, 2517), fan: Fan(id: 0, min: 2317, max: 7826, actual: 0), metadata: targetMetadata(), transport: io)
    }
    #expect(io.requests.map { $0[42] } == [9])
    #expect(io.commands.isEmpty)
}
