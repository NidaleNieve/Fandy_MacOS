import Foundation
import Testing
@testable import FandyHardware
import FandyCore
@Test func smcTypedFloatAndFixedPoint() {
    #expect(SMCDecoder.decode(type:"flt ",bytes:[0,0,0x3e,0x42])==47.5)
    #expect(SMCDecoder.decode(type:"ioft",bytes:[0,0x80,0x2f,0,0,0,0,0])==47.5)
    #expect(SMCDecoder.decode(type:"sp78",bytes:[0xff,0x80]) == -0.5)
    #expect(SMCDecoder.decode(type:"fpe2",bytes:[0x24,0x34])==2317)
    #expect(SMCDecoder.decode(type:"ui32",bytes:[0,0,1,0])==256)
}
@Test func smcDecoderRejectsNonfiniteUnknownAndWrongLengths() {
    #expect(SMCDecoder.decode(type:"flt ",bytes:[0,0,0x80,0x7f])==nil)
    #expect(SMCDecoder.decode(type:"flt ",bytes:[0,0,0xc0,0x7f])==nil)
    #expect(SMCDecoder.decode(type:"flt ",bytes:[0])==nil)
    #expect(SMCDecoder.decode(type:"hex_",bytes:[0,0,0,0])==nil)
}
@Test func unqualifiedMappingsCannotEnableTemperaturePolicies() {
    #expect(SensorRegistry.capabilities.permits(BuiltInProfiles.maximum))
    #expect(!SensorRegistry.capabilities.permits(BuiltInProfiles.gaming))
    #expect(SensorRegistry.capabilities.sensors.allSatisfy { $0.state == .pending })
    #expect(SensorRegistry.mappings.first{$0.role == .airflowTop}?.keys==["TaTP"])
}

@Test func fanModeDecoderRejectsUnqualifiedTypesAndStates() {
    #expect(SMCDecoder.fanMode(type:"ui8 ",bytes:[0]) == .automatic)
    #expect(SMCDecoder.fanMode(type:"ui8 ",bytes:[1]) == .manual)
    #expect(SMCDecoder.fanMode(type:"ui8 ",bytes:[3]) == .system)
    #expect(SMCDecoder.fanMode(type:"ui8 ",bytes:[255]) == nil)
    #expect(SMCDecoder.fanMode(type:"ui8 ",bytes:[]) == nil)
    #expect(SMCDecoder.fanMode(type:"flt ",bytes:[0,0,128,127]) == nil)
    #expect(SMCDecoder.fanMode(type:"ui32",bytes:[0,0,0,1]) == nil)
}

private final class StructSpy: SMCStructTransport {
    var requests: [[UInt8]] = []
    var response = SMCStructResponse(bytes: [UInt8](repeating: 0, count: 80), count: 80)
    func transact(_ request: [UInt8]) throws -> SMCStructResponse { requests.append(request); return response }
}
private func modeMetadata(_ mode: UInt8 = 1) -> DiscoveredSensor {
    DiscoveredSensor(key: "F0md", type: "ui8 ", size: 1, attributes: 208, bytes: [mode], value: Double(mode), error: nil)
}
@Test func automaticCommandUsesRecordedABIAndOnlyAutomaticMode() throws {
    let spy = StructSpy()
    try SMCAutomaticModeWriter.restore(fanID: 0, metadata: modeMetadata(), transport: spy)
    let request = try #require(spy.requests.first)
    #expect(request.count == 80)
    #expect(Array(request[0..<4]) == [0x64, 0x6d, 0x30, 0x46])
    #expect(Array(request[28..<32]) == [1, 0, 0, 0])
    #expect(request[42] == 6); #expect(request[48] == 0)
    #expect(request.enumerated().filter { $0.element != 0 }.map(\.offset) == [0, 1, 2, 3, 28, 42])
}
@Test func automaticCommandRejectsUnknownModesKeysAndMetadataWithoutTransport() throws {
    let spy = StructSpy()
    var badKey = modeMetadata(); badKey.key = "F0Tg"
    var badType = modeMetadata(); badType.type = "flt "
    var badSize = modeMetadata(); badSize.size = 32
    var badLength = modeMetadata(); badLength.bytes = [1, 1]
    for metadata in [badKey, badType, badSize, badLength, modeMetadata(255)] {
        #expect(throws: (any Error).self) { try SMCAutomaticModeWriter.restore(fanID: 0, metadata: metadata, transport: spy) }
    }
    #expect(throws: (any Error).self) { try SMCAutomaticModeWriter.restore(fanID: Int.max, metadata: modeMetadata(), transport: spy) }
    #expect(throws: (any Error).self) { try SMCAutomaticModeWriter.restore(fanID: 0, metadata: modeMetadata(3), transport: spy) }
    #expect(spy.requests.isEmpty)
}
@Test func automaticCommandChecksSMCResultAndOutputLength() {
    let spy = StructSpy(); var output = [UInt8](repeating: 0, count: 80); output[40] = 1
    for response in [SMCStructResponse(bytes: output, count: 80), SMCStructResponse(bytes: [], count: 80), SMCStructResponse(bytes: output, count: 79)] {
        spy.response = response
        #expect(throws: (any Error).self) { try SMCAutomaticModeWriter.restore(fanID: 0, metadata: modeMetadata(), transport: spy) }
    }
}

@Test func automaticCodecRejectsChangedAttributesAndReadErrors() {
    let spy = StructSpy()
    var attributes = modeMetadata(); attributes.attributes = 0
    var error = modeMetadata(); error.error = "read failed"
    for metadata in [attributes, error] {
        #expect(throws: (any Error).self) { try SMCAutomaticModeWriter.restore(fanID: 0, metadata: metadata, transport: spy) }
    }
    #expect(spy.requests.isEmpty)
}
