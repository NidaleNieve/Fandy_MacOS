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
    #expect(SensorRegistry.capabilities.verifiedRoles == SensorRegistry.reviewedComfortRoles)
    #expect(!SensorRole.safety.isSubset(of: SensorRegistry.capabilities.verifiedRoles))
    #expect(SensorRegistry.mappings.first{$0.role == .airflowTop}?.keys==["TaTP"])
}

@Test func envelopeManifestIsFixedCompleteAndDoesNotQualifyItself() throws {
    #expect(SensorRegistry.gpuRegionCandidates.count == 42)
    #expect(SensorRegistry.chipEnvelopeKeys.count == 105)
    #expect(Set(SensorRegistry.chipEnvelopeKeys).count == 105)
    #expect(!SensorRegistry.chipEnvelopeKeys.contains("Tg1g"))
    let mapping = SensorRegistry.mappings.first { $0.role == .socPeak }!
    #expect(mapping.reduction == .maximum)
    #expect(mapping.keys == SensorRegistry.chipEnvelopeKeys)
    #expect(!SensorRegistry.capabilities.verifiedRoles.contains(.socPeak))
    let sample: (String) throws -> DiscoveredSensor = { key in
        DiscoveredSensor(key: key, type: "flt ", size: 4, attributes: 0, bytes: [0,0,0,0],
                         value: key == "Tg3x" ? 85 : key == "Tm04" ? 80 : 40, error: nil, sampledAt: 10.1)
    }
    #expect(mapping.reading(sequence: 1, qualified: false, now: 10, read: sample).celsius == 85)
    #expect(mapping.reading(sequence: 1, qualified: false, now: 10, read: sample).health == .unverified)
    let missing = mapping.reading(sequence: 1, qualified: true, now: 10) { key in
        if key == "Tm04" { throw HardwareError.invalidMetadata }; return try sample(key)
    }
    #expect(missing.celsius == nil); #expect(missing.health == .missing)
}

@Test func expandedRegistryStatusFitsTheNarrowWireLimit() throws {
    let snapshot = HardwareSnapshot(at: 10, sensors: SensorRegistry.mappings.map {
        SensorReading($0.role, 40, at: 10, sequence: 1, health: .unverified)
    }, fans: [Fan(id: 0, min: 2300, max: 7800, actual: 0), Fan(id: 1, min: 2300, max: 7800, actual: 0)])
    let status = HelperStatus(automaticVerified: true, manualQualified: true, snapshot: snapshot, capabilities: SensorRegistry.capabilities)
    #expect(try Wire.encode(status).count < Wire.maxBytes)
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

private func temperatureSample(_ key: String, _ value: Float, at time: Double = 10) -> DiscoveredSensor {
    let raw = value.bitPattern
    return DiscoveredSensor(key: key, type: "flt ", size: 4, attributes: 0,
        bytes: (0..<4).map { UInt8(truncatingIfNeeded: raw >> ($0 * 8)) }, value: Double(value), error: nil, sampledAt: time)
}
@Test func independentSensorGroupsAndCompletionTimestamps() {
    let samples = ["Tp00": temperatureSample("Tp00", 40, at: 10.2), "Tm00": temperatureSample("Tm00", 60, at: 10.4)]
    let average = SensorMapping(role: .cpuAverage, keys: ["Tp00"])
    let peak = SensorMapping(role: .cpuPeak, keys: ["Tp00", "Tm00"], reduction: .maximum)
    let read: (String) throws -> DiscoveredSensor = { try #require(samples[$0]) }
    let a = average.reading(sequence: 3, qualified: true, now: 10, read: read)
    let p = peak.reading(sequence: 3, qualified: true, now: 10, read: read)
    #expect(a.celsius == 40); #expect(p.celsius == 60)
    #expect(a.sampledAt == 10.2); #expect(p.sampledAt == 10.2)
    #expect(a.sequence == 3); #expect(p.health == .valid)
    #expect(throws: (any Error).self) { _ = try p.value(now: 13.3) }
}
@Test func missingOrMalformedMemberNeverBecomesPartialAggregate() {
    let mapping = SensorMapping(role: .gpuPeak, keys: ["Tg0U", "Tg1Y"], reduction: .maximum)
    var malformed = temperatureSample("Tg1Y", 60); malformed.type = "ioft"
    let good = temperatureSample("Tg0U", 50)
    for bad in [malformed, temperatureSample("Tg1Y", .nan), temperatureSample("Tg1Y", .infinity)] {
        let reading = mapping.reading(sequence: 1, qualified: true, now: 10, read: { $0 == "Tg0U" ? good : bad })
        #expect(reading.celsius == nil); #expect(reading.health == .missing)
    }
    let missing = mapping.reading(sequence: 1, qualified: true, now: 10, read: { key in
        guard key == "Tg0U" else { throw HardwareError.invalidKey }; return good
    })
    #expect(missing.celsius == nil)
    let duplicate = SensorMapping(role: .gpuPeak, keys: ["Tg0U", "Tg0U"])
    #expect(duplicate.reading(sequence: 1, qualified: true, now: 10, read: { _ in good }).health == .corrupt)
}
@Test func sensorRegistryDoesNotSilentlyRequireAbsentGenericGPUKey() {
    #expect(SensorRegistry.publishedGPUKeys.contains("Tg1g"))
    #expect(!SensorRegistry.mappings.first { $0.role == .gpuPeak }!.keys.contains("Tg1g"))
    #expect(SensorRegistry.mappings.first { $0.role == .cpuPeak }!.reduction == .maximum)
}

@Test func bothObservedCPUFamiliesAreIncludedOnlyAsExplicitCandidates() {
    #expect(SensorRegistry.cpuRegionCandidates.count == 63)
    #expect(SensorRegistry.cpuRegionCandidates.contains("Tm04"))
    #expect(SensorRegistry.cpuRegionCandidates.contains("Tp00"))
    #expect(!SensorRegistry.capabilities.verifiedRoles.contains(.cpuPeak))
    #expect(!SensorRegistry.capabilities.canQualifyCurves)
}
