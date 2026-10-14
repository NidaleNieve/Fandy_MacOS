import Foundation
import Testing
import FandyCore
@testable import FandyHardware

private final class PacketSMC: SMCStructTransport {
    var commands: [UInt8] = []; var result: UInt8 = 0; var shortReply = false
    var value: UInt32 = Float(42).bitPattern
    func transact(_ request: [UInt8]) throws -> SMCStructResponse {
        #expect(request.count == 80); commands.append(request[42])
        var reply = [UInt8](repeating: 0, count: 80); reply[40] = result
        if request[42] == 9 {
            reply[28] = 4; reply.replaceSubrange(32..<36, with: Array("flt ".utf8).reversed()); reply[36] = 128
        } else if request[42] == 5 {
            reply.replaceSubrange(48..<52, with: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        return .init(bytes: reply, count: shortReply ? 79 : 80)
    }
}
@Test func productionSMCReaderUsesInjectedPacketsAndCachesOnlySuccessfulMetadata() throws {
    let transport = PacketSMC(); let reader = SMCReader(transport: transport, clock: { 20 })
    #expect(try reader.read("Tp01").value == 42)
    transport.value = Float(45).bitPattern
    #expect(try reader.read("Tp01").value == 45)
    #expect(transport.commands == [9,5,5])
    #expect(try reader.read("Tp01").sampledAt == 20)
    transport.result = 0x84
    #expect(throws: (any Error).self) { try reader.read("Tp01") }
    transport.result = 0
    #expect(try reader.read("Tp01").value == 45)
    #expect(transport.commands.suffix(2) == [9,5])
    transport.shortReply = true
    #expect(throws: (any Error).self) { try reader.read("Tp01") }
}
@Test func installationPolicyNeedsNoUnprivilegedSMCRead() {
    let m2 = DeviceIdentity(model: "Mac14,9", chip: "Apple M2 Pro", appleSilicon: true)
    #expect(DeviceRegistry.canInstallHelper(identity: m2))
    #expect(!DeviceRegistry.canInstallHelper(identity: .init(model: "MacBookPro16,1", chip: "Intel", appleSilicon: false)))
    #expect(!DeviceRegistry.declaredCapabilities(identity: m2).canControl)
}

@Test func invalidTemperatureValueDoesNotPreserveCachedMetadata() throws {
    let packets = PacketSMC()
    let source = SMCReader(transport: packets)
    packets.value = Float.nan.bitPattern
    #expect(try source.read("Tp01").value == nil)
    packets.value = Float(42).bitPattern
    #expect(try source.read("Tp01").value == 42)
    #expect(packets.commands == [9,5,9,5])
}

@Test func modeDiscoveryPreservesFirmwareFailureInsteadOfCallingItAbsent() throws {
    let packets = PacketSMC(); packets.result = 0x82
    do {
        _ = try SMCReader(transport: packets).fanModeKey(0)
        Issue.record("Expected firmware failure")
    } catch let failure as SMCReadFailure { #expect(failure.failure.code == 0x82) }
}
