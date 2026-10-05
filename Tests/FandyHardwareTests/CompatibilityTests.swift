import Foundation
import Testing
import FandyCore
@testable import FandyHardware

/// Synthetic protocol fixtures populated from pinned reference facts. Not hardware
/// recordings or a claim that Fandy has physically tested another Mac.
private final class CompatibilitySMC: SMCStructTransport {
    let identity: DeviceIdentity
    var values: [String: DiscoveredSensor] = [:]
    var writes: [(String, Double)] = []
    var failKey: String?
    var failRead: String?
    var blockDirect = false
    var now = 10.0
    init(model: String = "Mac16,8", chip: String = "Apple M4 Pro", count: Int = 2, fixed: Bool = false, forceTest: Bool = true) {
        identity = DeviceIdentity(model: model, chip: chip, appleSilicon: true)
        put("FNum", Double(count), "ui8 ")
        for id in 0..<count {
            put("F\(id)\(identity.family == .m5 ? "md" : "Md")", 0, "ui8 ")
            for (suffix, value) in [("Mn", 1200.0 + Double(id) * 100), ("Mx", 6000.0 + Double(id) * 500), ("Ac", 2000.0), ("Tg", 2000.0)] {
                put("F\(id)\(suffix)", value, fixed ? "fpe2" : "flt ", attributes: 212)
            }
        }
        if forceTest { put("Ftst", 0, "ui8 ") }
        let keys = DeviceRegistry.candidates(for: identity)
        for key in keys.efficiency + keys.performance + keys.gpu + ["Ts0P","Ts1P","TaLP","TaTP","TaRF","TW0P"] { put(key, 40, "flt ") }
    }
    func put(_ key: String, _ value: Double, _ type: String, attributes: UInt8 = 208) {
        let bytes: [UInt8]
        switch type {
        case "ui8 ": bytes = [UInt8(value)]
        case "fpe2": let n = UInt16(value * 4); bytes = [UInt8(n >> 8), UInt8(truncatingIfNeeded: n)]
        case "sp78": let n = UInt16(value * 256); bytes = [UInt8(n >> 8), UInt8(truncatingIfNeeded: n)]
        default: let n = Float(value).bitPattern; bytes = (0..<4).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }
        }
        values[key] = DiscoveredSensor(key: key, type: type, size: bytes.count, attributes: attributes, bytes: bytes,
            value: value, error: nil, sampledAt: now)
    }
    func read(_ key: String) throws -> DiscoveredSensor {
        if failRead == key { throw HardwareError.invalidMetadata }
        guard var value = values[key] else { throw HardwareError.smc(Int32(bitPattern: 0xFAD00084)) }
        value.sampledAt = now; return value
    }
    func fans() throws -> [Fan] {
        try (0..<Int(read("FNum").value!)).map { id in
            let mode = try read("F\(id)\(identity.family == .m5 ? "md" : "Md")")
            return Fan(id: id, min: try read("F\(id)Mn").value!, max: try read("F\(id)Mx").value!,
                actual: try read("F\(id)Ac").value!, target: try read("F\(id)Tg").value!, mode: FanMode(rawValue: Int(mode.value!))!)
        }
    }
    func transact(_ input: [UInt8]) throws -> SMCStructResponse {
        let key = String(bytes: input[0..<4].reversed(), encoding: .ascii)!
        let old = try read(key)
        var output = [UInt8](repeating: 0, count: 80)
        if input[42] == 9 {
            output[28] = UInt8(old.size); output.replaceSubrange(32..<36, with: old.type.utf8.reversed()); output[36] = old.attributes
        } else if input[42] == 6 {
            if failKey == key { output[40] = 0x82 }
            else if blockDirect && key.hasSuffix("Md") && input[48] == 1 && values["Ftst"]?.value == 0 { output[40] = 0x82 }
            else {
                let value = SMCDecoder.decode(type: old.type, bytes: Array(input[48..<(48 + old.size)]))!
                put(key, value, old.type, attributes: old.attributes); writes.append((key, value))
                if key == "Ftst" && value == 1 {
                    for id in 0..<Int(values["FNum"]!.value!) { put("F\(id)Md", 0, "ui8 ") }
                }
            }
        } else { throw HardwareError.invalidMetadata }
        return SMCStructResponse(bytes: output, count: 80)
    }
    func interface() throws -> FanInterface { try FanInterface.discover(identity: identity, read: read) }
    func apply(check: () throws -> Void = {}) throws {
        try ReferenceFanTransaction.apply([FanTarget(0, 2500), FanTarget(1, 2600)], interface: interface(), transport: self,
            clock: { self.now }, read: read, fans: fans, check: check, pause: { self.now += 0.05 })
    }
}

@Test(arguments: [("MacBookPro18,3", "Apple M1 Pro"), ("Mac14,9", "Apple M2 Pro"),
    ("Mac15,6", "Apple M3 Pro"), ("Mac16,8", "Apple M4 Pro"), ("Mac17,8", "Apple M5 Pro")])
func referenceFamiliesSelectTheirOwnCompleteGroups(_ item: (String, String)) throws {
    let fixture = CompatibilitySMC(model: item.0, chip: item.1, forceTest: !item.1.contains("M5"))
    let device = DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read)
    #expect(device.capabilities.compatibilityEvidence == .referenceSupported)
    #expect(device.capabilities.permits(BuiltInProfiles.systemPlus))
    #expect(device.capabilities.permits(BuiltInProfiles.gaming))
    #expect(device.capabilities.permits(BuiltInProfiles.coolChassis))
    #expect(device.capabilities.chipPolicy == .cpuGPU)
    #expect(device.mappings.first { $0.role == .cpuPeak }?.reduction == .maximum)
    #expect(device.capabilities.sensors.allSatisfy { $0.state != .verified })
    #expect(!device.acquisitionKeys.contains("Tg3x")) // M5 local-only manifest never leaks to another model.
}
@Test func chipIdentityAndNotebookRosterAreIndependent() {
    #expect(!DeviceIdentity(model: "Mac16,8", chip: "Apple M3 Pro", appleSilicon: true).supportedNotebook)
    #expect(!DeviceIdentity(model: "Mac16,8", chip: "Apple M4 Pro", appleSilicon: false).supportedNotebook)
    #expect(!DeviceIdentity(model: "MacBookPro16,1", chip: "Intel Core i9", appleSilicon: false).supportedNotebook)
    #expect(!DeviceIdentity(model: "Mac16,10", chip: "Apple M4", appleSilicon: true).supportedNotebook)
    #expect(!DeviceIdentity(model: "Mac17,9", chip: "Apple M50 Pro", appleSilicon: true).supportedNotebook)
}
@Test func variantAbsentKeysAreResolvedOnceButAcquisitionNeverDropsMembers() throws {
    let fixture = CompatibilitySMC(); let absent = DeviceRegistry.candidates(for: fixture.identity).performance.last!
    fixture.values.removeValue(forKey: absent)
    let device = DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read)
    #expect(device.capabilities.permits(BuiltInProfiles.systemPlus))
    #expect(!device.acquisitionKeys.contains(absent))
    let peak = try #require(device.mappings.first { $0.role == .cpuPeak })
    fixture.failRead = peak.keys.first
    let reading = peak.reading(sequence: 2, qualified: true, now: 10, read: fixture.read)
    #expect(reading.health == .missing); #expect(reading.celsius == nil)
}
@Test func initialCorruptOrFailedCandidateCannotSilentlyQualifyPartialChipCoverage() {
    let fixture = CompatibilitySMC(); fixture.failRead = DeviceRegistry.candidates(for: fixture.identity).performance.last!
    let device = DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read)
    #expect(!device.capabilities.permits(BuiltInProfiles.systemPlus))
    #expect(device.capabilities.canRestore); #expect(device.capabilities.permits(BuiltInProfiles.maximum))
}
@Test func missingCPUClusterAndComfortRoleOnlyBlockDependentPolicies() {
    let fixture = CompatibilitySMC()
    for key in DeviceRegistry.candidates(for: fixture.identity).efficiency { fixture.values.removeValue(forKey: key) }
    #expect(!DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read).capabilities.permits(BuiltInProfiles.gaming))
    let healthy = CompatibilitySMC(); healthy.values.removeValue(forKey: "Ts1P")
    let cap = DeviceRegistry.resolve(identity: healthy.identity, read: healthy.read).capabilities
    #expect(cap.permits(BuiltInProfiles.gaming)); #expect(!cap.permits(BuiltInProfiles.coolChassis))
    #expect(cap.reasonUnavailable(BuiltInProfiles.coolChassis).contains("Trackpad Actuator"))
}
@Test func M4BaseAndProMaxGPUAnchorsAreDifferent() {
    let base = DeviceRegistry.candidates(for: DeviceIdentity(model: "Mac16,1", chip: "Apple M4", appleSilicon: true))
    let pro = DeviceRegistry.candidates(for: DeviceIdentity(model: "Mac16,8", chip: "Apple M4 Pro", appleSilicon: true))
    #expect(base.gpu.contains("Tg0G")); #expect(!base.gpu.contains("Tg1U"))
    #expect(pro.gpu.contains("Tg1U")); #expect(!pro.gpu.contains("Tg0G"))
}
@Test func referenceFanTopologyIsDynamicAndUnsupportedMetadataFailsClosed() throws {
    let single = CompatibilitySMC(model: "MacBookPro17,1", chip: "Apple M1", count: 1, forceTest: false)
    #expect(try single.interface().fanIDs == [0])
    let fixed = CompatibilitySMC(fixed: true)
    #expect(try fixed.interface().targetFormats[1] == .fixed)
    let ambiguous = CompatibilitySMC(); ambiguous.put("F0md", 0, "ui8 ")
    #expect(throws: (any Error).self) { try ambiguous.interface() }
    let corrupt = CompatibilitySMC(); corrupt.values["Ftst"]!.attributes = 0
    #expect(throws: (any Error).self) { try corrupt.interface() }
    let wrongMode = CompatibilitySMC(); wrongMode.put("F0Md", 9, "ui8 ")
    #expect(throws: (any Error).self) { try wrongMode.interface() }
}
@Test func referenceDirectTransactionTargetsEachFanBeforeNextAdmission() throws {
    let fixture = CompatibilitySMC(); try fixture.apply()
    #expect(fixture.writes.map(\.0) == ["F0Md","F0Tg","F1Md","F1Tg"])
    #expect(fixture.writes.map(\.1) == [1,2500,1,2600])
}
@Test func protectedM4HandoverIsBoundedAndUsesOnlyReviewedKeys() throws {
    let fixture = CompatibilitySMC(); fixture.blockDirect = true; try fixture.apply()
    #expect(fixture.writes.map(\.0) == ["Ftst","F0Md","F0Tg","F1Md","F1Tg"])
    #expect(fixture.values["Ftst"]?.value == 1)
    #expect(fixture.now < 17)
}
@Test func referenceFixedPointTargetsAndTwoDifferentBoundsAreValidated() throws {
    let fixture = CompatibilitySMC(fixed: true); try fixture.apply()
    #expect(fixture.values["F0Tg"]?.value == 2500); #expect(fixture.values["F1Tg"]?.value == 2600)
    let descriptor = try fixture.interface()
    let fan = try fixture.fans()[0]
    #expect(throws: (any Error).self) { try descriptor.writeTarget(FanTarget(0, 6500), fan: fan, metadata: fixture.read("F0Tg"), transport: fixture) }
    #expect(throws: (any Error).self) { try descriptor.writeTarget(FanTarget(Int.max, .nan), fan: fan, metadata: fixture.read("F0Tg"), transport: fixture) }
}
@Test func handoverDeadlineCancellationAndUnexpectedOwnershipAreRejected() {
    var now = 10.0
    #expect(throws: ControlError.staleSession) {
        try FanHandover.awaitAutomatic(ids: [0,1], deadline: 10.2, clock: { now }, cancelled: {}, read: { _ in .system }, pause: { now += 0.1 })
    }
    #expect(throws: ControlError.staleSession) {
        try FanHandover.awaitAutomatic(ids: [0], deadline: 12, clock: { 10 }, cancelled: { throw ControlError.staleSession }, read: { _ in .automatic }, pause: {})
    }
    #expect(throws: ControlError.restorationUnverified) {
        try FanHandover.awaitAutomatic(ids: [0], deadline: 12, clock: { 10 }, cancelled: {}, read: { _ in .manual }, pause: {})
    }
}
@Test func cancelledAdmissionAndPartialTargetFailureCannotFinishTransaction() {
    let fixture = CompatibilitySMC(); let fence = HardwareOperationFence(); let token = fence.token(); fence.cancel()
    #expect(throws: ControlError.staleSession) { try fixture.apply(check: { try fence.require(token) }) }
    #expect(fixture.writes.isEmpty)
    let failure = CompatibilitySMC(); failure.failKey = "F1Tg"
    #expect(throws: (any Error).self) { try failure.apply() }
    #expect(failure.writes.last?.0 == "F1Md")
}
@Test func referenceRestorationDoesNotWriteTargetsAndClearsGlobalFlag() throws {
    let fixture = CompatibilitySMC(); fixture.put("Ftst", 1, "ui8 "); fixture.put("F0Md", 1, "ui8 "); fixture.put("F1Md", 1, "ui8 ")
    let descriptor = try fixture.interface()
    for id in descriptor.fanIDs { try descriptor.restoreMode(id: id, metadata: fixture.read(descriptor.modeKeys[id]!), transport: fixture) }
    try descriptor.writeForceTest(false, metadata: fixture.read("Ftst"), transport: fixture)
    #expect(fixture.writes.map(\.0) == ["F0Md","F1Md","Ftst"])
    #expect(fixture.values["Ftst"]?.value == 0)
}
@Test func compatibilityEvidenceDecodesOldCapabilitiesAndNeverCrossesModelAuthority() throws {
    let old = Data(#"{"model":"Mac17,9","stage":"observation","sensors":[],"topology":"pending","automaticRestoration":"pending","manualTransaction":"pending"}"#.utf8)
    #expect(try JSONDecoder().decode(HardwareCapabilities.self, from: old).compatibilityEvidence == .unsupported)
    let fixture = CompatibilitySMC(); let cap = DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read).capabilities
    #expect(!cap.forMachine("MacBookPro16,1").canControl)
    #expect(try Wire.encode(HelperStatus(automaticVerified: true, capabilities: cap)).count < Wire.maxBytes)
}

@Test func protectedSystemRestorationSkipsRejectedModeWriteButRequiresGlobalRelease() throws {
    let fixture = CompatibilitySMC(); fixture.put("F0Md", 3, "ui8 "); fixture.put("F1Md", 3, "ui8 ")
    let descriptor = try fixture.interface()
    for id in descriptor.fanIDs { try descriptor.restoreMode(id: id, metadata: fixture.read(descriptor.modeKeys[id]!), transport: fixture) }
    try descriptor.writeForceTest(false, metadata: fixture.read("Ftst"), transport: fixture)
    #expect(fixture.writes.map(\.0) == ["Ftst"])
}
@Test func lostForceTestOwnershipCannotBeReassertedOrLowerTargets() throws {
    let fixture = CompatibilitySMC(); fixture.blockDirect = true
    var lost = false
    #expect(throws: ControlError.restorationUnverified) {
        try fixture.apply(check: {
            if fixture.values["Ftst"]?.value == 1 && !lost { lost = true; fixture.put("Ftst", 0, "ui8 ") }
        })
    }
    #expect(lost); #expect(!fixture.writes.contains { $0.0.hasSuffix("Tg") })
    #expect(fixture.writes.filter { $0.0 == "Ftst" }.count == 1)
}
@Test func localM5RecipeDoesNotGainLegacyOrUnknownTargetAuthority() throws {
    let fixture = CompatibilitySMC(model: "Mac17,9", chip: "Apple M5 Pro", forceTest: false)
    let local = DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read)
    #expect(local.capabilities.compatibilityEvidence == .locallyTested)
    #expect(local.mappings.map(\.keys) == SensorRegistry.mappings.map(\.keys))
    fixture.values["F0Tg"]!.attributes = 0
    let restorationOnly = DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read)
    #expect(restorationOnly.capabilities.canRestore); #expect(!restorationOnly.capabilities.canControl)
    fixture.put("Ftst", 0, "ui8 ")
    #expect(!DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read).capabilities.canRestore)
}
private final class ReferenceRestorationIO: FanHardwareIO, @unchecked Sendable {
    let fixture: CompatibilitySMC
    let descriptor: FanInterface
    var attempts: [Int] = []
    init(_ fixture: CompatibilitySMC) throws { self.fixture = fixture; descriptor = try fixture.interface() }
    func enumerateFans() throws -> [Fan] { try fixture.fans() }
    func fanIDsForRestoration() throws -> [Int] { descriptor.fanIDs }
    func readMode(fanID: Int) throws -> FanMode { FanMode(rawValue: Int(try fixture.read(descriptor.modeKeys[fanID]!).value!))! }
    func acceptsAutomatic(_ mode: FanMode) -> Bool { mode.isAutomatic }
    func restorationNeedsWrite(fanID: Int, mode: FanMode) -> Bool { !mode.isAutomatic }
    func setAutomatic(fanID: Int) throws {
        attempts.append(fanID)
        try descriptor.restoreMode(id: fanID, metadata: fixture.read(descriptor.modeKeys[fanID]!), transport: fixture)
    }
    func finishAutomaticRestoration() throws {
        let flag = try fixture.read("Ftst"); try FanInterface.validateFlag(flag)
        if flag.value != 0 { try descriptor.writeForceTest(false, metadata: flag, transport: fixture) }
        guard try fixture.read("Ftst").value == 0 else { throw ControlError.restorationUnverified }
    }
    func applyValidatedTargets(_ targets: [FanTarget]) throws { throw ControlError.hardwareUnqualified }
}
@Test func startupReleaseAndPartialFailureAlwaysAttemptEveryFanAndGlobalFlag() throws {
    let fixture = CompatibilitySMC(); fixture.put("Ftst", 1, "ui8 ")
    fixture.put("F0Md", 1, "ui8 "); fixture.put("F1Md", 1, "ui8 ")
    let io = try ReferenceRestorationIO(fixture)
    fixture.failKey = "F0Md"
    let partial = try FanRestoration.report(using: io)
    #expect(io.attempts == [0,1]); #expect(!partial.verified)
    #expect(partial.fans[1].releasedManual); #expect(fixture.values["Ftst"]?.value == 0)
    fixture.failKey = nil
    #expect(try FanRestoration.report(using: io).verified)
    fixture.put("Ftst", 1, "ui8 "); fixture.failKey = "Ftst"
    let globalFailure = try FanRestoration.report(using: io)
    #expect(!globalFailure.verified); #expect(globalFailure.globalReleaseFailure != nil)
    #expect(globalFailure.fans.allSatisfy { $0.verified })
}

@Test func modeAliasTransportFailureCannotMasqueradeAsNotFound() throws {
    let fixture = CompatibilitySMC(); fixture.failRead = "F0md"
    #expect(throws: (any Error).self) { try fixture.interface() }
    #expect(!DeviceRegistry.resolve(identity: fixture.identity, read: fixture.read).capabilities.canControl)
}
@Test func corruptBaselinePreventsAnyReferenceManualAdmission() throws {
    let fixture = CompatibilitySMC(), descriptor = try fixture.interface()
    #expect(throws: (any Error).self) {
        try ReferenceFanTransaction.apply([FanTarget(0,2500),FanTarget(1,2600)], interface: descriptor, transport: fixture,
            clock: { 10 }, read: fixture.read, fans: {
                var fans = try fixture.fans(); fans[0].actualRPM = .nan; return fans
            }, check: {}, pause: {})
    }
    #expect(fixture.writes.isEmpty)
}

@Test func connectionCancellationCannotRevokeAnotherOwnersTransaction() throws {
    let fence = HardwareOperationFence(), a = UUID(), b = UUID()
    #expect(fence.connect(owner: a)); #expect(fence.connect(owner: b))
    let aToken = try fence.token(owner: a), bToken = try fence.token(owner: b)
    let fixture = CompatibilitySMC()
    fence.cancel(owner: b)
    #expect(throws: ControlError.staleSession) { try fence.require(bToken) }
    try fixture.apply(check: { try fence.require(aToken) })
    #expect(!fixture.writes.isEmpty)
    // Disconnect must revoke queued and watchdog work with the same owner token.
    let beforeDisconnect = try fence.token(owner: b)
    fence.disconnected(owner: b)
    #expect(throws: ControlError.staleSession) { try fence.require(beforeDisconnect) }
    try fence.require(aToken)
    fence.cancel(owner: a)
    #expect(throws: ControlError.staleSession) { try fence.require(aToken) }
}

@Test func globalCancellationRevokesEveryOwnerAndUnscopedWork() throws {
    let fence = HardwareOperationFence(), owners = [UUID(), UUID()]
    let global = fence.token()
    for owner in owners { #expect(fence.connect(owner: owner)) }
    let tokens = try owners.map { try fence.token(owner: $0) }
    fence.cancel()
    for token in tokens + [global] { #expect(throws: ControlError.staleSession) { try fence.require(token) } }
    for owner in owners { try fence.require(fence.token(owner: owner)) }
}

@Test func cancellationConnectionsAreBoundedAndOldTokensNeverRevive() throws {
    let fence = HardwareOperationFence(), owners = (0..<8).map { _ in UUID() }
    for owner in owners { #expect(fence.connect(owner: owner)) }
    #expect(!fence.connect(owner: UUID())); #expect(!fence.connect(owner: owners[0]))
    let old = try fence.token(owner: owners[0])
    fence.disconnected(owner: owners[0])
    #expect(throws: ControlError.staleSession) { try fence.token(owner: owners[0]) }
    fence.cancel(owner: UUID()) // Unknown peers cannot consume slots.
    #expect(fence.connect(owner: owners[0]))
    #expect(throws: ControlError.staleSession) { try fence.require(old) }
    try fence.require(fence.token(owner: owners[0]))
}

@Test func concurrentOwnerCancellationLeavesOtherOwnerValid() throws {
    let fence = HardwareOperationFence(), a = UUID(), b = UUID()
    #expect(fence.connect(owner: a)); #expect(fence.connect(owner: b))
    let token = try fence.token(owner: a)
    DispatchQueue.concurrentPerform(iterations: 64) { _ in
        fence.cancel(owner: b)
        if let other = try? fence.token(owner: b) { try? fence.require(other) }
        #expect(throws: Never.self) { try fence.require(token) }
    }
    try fence.require(token)
}

@Test(arguments: [false, true])
func scopedCancellationDuringProtectedHandoverRespectsTransactionOwner(cancelOwner: Bool) throws {
    let fixture = CompatibilitySMC(); fixture.blockDirect = true
    let fence = HardwareOperationFence(), owner = UUID(), other = UUID()
    #expect(fence.connect(owner: owner)); #expect(fence.connect(owner: other))
    let token = try fence.token(owner: owner)
    var observedHandover = false
    func check() throws {
        if fixture.values["Ftst"]?.value == 1 {
            observedHandover = true
            fence.cancel(owner: cancelOwner ? owner : other)
        }
        try fence.require(token)
    }
    if cancelOwner {
        #expect(throws: ControlError.staleSession) { try fixture.apply(check: check) }
        #expect(fixture.writes.allSatisfy { !$0.0.hasSuffix("Tg") })
    } else {
        try fixture.apply(check: check)
        #expect(fixture.writes.suffix(2).map(\.0) == ["F1Md", "F1Tg"])
    }
    #expect(observedHandover)
}

@Test func directAdmissionTargetsEachFanBeforeNextModeAndPreflightsAllMetadata() throws {
    let fixture = CompatibilitySMC(model: "Mac17,9", chip: "Apple M5 Pro", forceTest: false)
    fixture.put("F0Tg", 6000, "flt ", attributes: 212); fixture.put("F1Tg", 6500, "flt ", attributes: 212)
    var events: [FanTransition] = []
    try DirectFanTransaction.apply([FanTarget(0,2500),FanTarget(1,2600)], transport: fixture,
        read: fixture.read, fans: fixture.fans, clock: { fixture.now }, check: {}, event: { events.append($0) })
    #expect(fixture.writes.map(\.0) == ["F0md","F0Tg","F1md","F1Tg"])
    #expect(events.map(\.stage) == [.modeWritten,.targetWritten,.modeWritten,.targetWritten,.acknowledged,.acknowledged])
    #expect(events[0].previousTarget == 6000 && events[2].previousTarget == 6500)
    let corrupt = CompatibilitySMC(model: "Mac17,9", chip: "Apple M5 Pro", forceTest: false)
    corrupt.values["F1Tg"]!.attributes = 0
    #expect(throws: (any Error).self) {
        try DirectFanTransaction.apply([FanTarget(0,2500),FanTarget(1,2600)], transport: corrupt,
            read: corrupt.read, fans: corrupt.fans, clock: { 10 }, check: {})
    }
    #expect(corrupt.writes.isEmpty)
}

@Test func referenceAlreadyAutomaticDoesNotWriteProtectedModesOrClaimManualRelease() throws {
    let fixture = CompatibilitySMC(model: "Mac14,9", chip: "Apple M2 Pro")
    let descriptor = try fixture.interface()
    for id in descriptor.fanIDs { try descriptor.restoreMode(id: id, metadata: fixture.read(descriptor.modeKeys[id]!), transport: fixture) }
    #expect(fixture.writes.isEmpty)
}

@Test func alreadyAutomaticReferenceRestorationVerifiesWithoutProtectedWrite() throws {
    let fixture = CompatibilitySMC(model: "Mac14,9", chip: "Apple M2 Pro")
    let io = try ReferenceRestorationIO(fixture)
    let report = try FanRestoration.report(using: io)
    #expect(report.verified && report.fans.allSatisfy { $0.alreadyAutomatic == true && !$0.releasedManual && $0.commandSucceeded == false })
    #expect(io.attempts.isEmpty && !fixture.writes.contains { $0.0.hasSuffix("Md") })
    fixture.failKey = "Ftst"
    #expect(try FanRestoration.report(using: io).verified) // A cleared flag needs no write.
    fixture.put("Ftst", 1, "ui8 ")
    #expect(!(try FanRestoration.report(using: io)).verified)
}
@Test func referenceMixedOwnershipUpdatesEveryTargetAndTargetRejectionDoesNotUnlock() throws {
    let fixture = CompatibilitySMC(); fixture.put("F0Md", 1, "ui8 ")
    try fixture.apply()
    #expect(fixture.values["F0Tg"]?.value == 2500 && fixture.values["F1Tg"]?.value == 2600)
    let rejected = CompatibilitySMC(); rejected.failKey = "F0Tg"
    #expect(throws: (any Error).self) { try rejected.apply() }
    #expect(!rejected.writes.contains { $0.0 == "Ftst" })
}
@Test func referenceNarrowAdmissionHonorsCancellationBeforeTarget() throws {
    let fixture = CompatibilitySMC(), descriptor = try fixture.interface()
    #expect(throws: ControlError.staleSession) {
        try ReferenceFanTransaction.apply([FanTarget(0,2500),FanTarget(1,2600)], interface: descriptor, transport: fixture,
            clock: { fixture.now }, read: fixture.read, fans: fixture.fans, check: {},
            cancelled: { if fixture.values["F0Md"]?.value == 1 { throw ControlError.staleSession } }, pause: {})
    }
    #expect(fixture.writes.map(\.0) == ["F0Md"])
    #expect(try FanRestoration.report(using: ReferenceRestorationIO(fixture)).verified)
    #expect(try fixture.fans().allSatisfy { $0.mode.isAutomatic })
}
private final class DirectRestorationIO: FanHardwareIO, @unchecked Sendable {
    let fixture: CompatibilitySMC
    init(_ fixture: CompatibilitySMC) { self.fixture = fixture }
    func enumerateFans() throws -> [Fan] { try fixture.fans() }
    func readMode(fanID: Int) throws -> FanMode { try fixture.fans().first { $0.id == fanID }!.mode }
    func setAutomatic(fanID: Int) throws {
        try SMCAutomaticModeWriter.restore(fanID: fanID, metadata: fixture.read("F\(fanID)md"), transport: fixture)
    }
    func applyValidatedTargets(_ targets: [FanTarget]) throws {
        try DirectFanTransaction.apply(targets, transport: fixture, read: fixture.read, fans: fixture.fans, clock: { self.fixture.now }, check: {})
    }
}
@Test func directPartialTargetFailureRestoresEveryAdmittedFan() throws {
    let fixture = CompatibilitySMC(model: "Mac17,9", chip: "Apple M5 Pro", forceTest: false)
    fixture.failKey = "F1Tg"
    #expect(throws: (any Error).self) { try FanRestoration.apply([FanTarget(0,2500),FanTarget(1,2600)], using: DirectRestorationIO(fixture)) }
    #expect(fixture.writes.suffix(2).map(\.0) == ["F0md", "F1md"])
    #expect(try fixture.fans().allSatisfy { $0.mode == .automatic })
}

@Test func directAdmissionDefersFullEnumerationUntilEveryFanIsTargeted() throws {
    let fixture = CompatibilitySMC(model: "Mac17,9", chip: "Apple M5 Pro", forceTest: false)
    var readsDuringMixedModes = 0
    try DirectFanTransaction.apply([FanTarget(0,2500),FanTarget(1,2600)], transport: fixture,
        read: fixture.read, fans: {
            let fans = try fixture.fans()
            if Set(fans.map(\.mode)).count > 1 { readsDuringMixedModes += 1 }
            return fans
        }, clock: { fixture.now }, check: {})
    #expect(readsDuringMixedModes == 0)
    #expect(fixture.writes.map(\.0) == ["F0md","F0Tg","F1md","F1Tg"])
}
