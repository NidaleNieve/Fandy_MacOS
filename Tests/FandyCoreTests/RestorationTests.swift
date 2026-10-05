import Foundation
import Testing
@testable import FandyCore
// Each test owns its spy. Production serializes I/O; unchecked Sendable supports that protocol boundary.
final class FanSpy: FanHardwareIO, @unchecked Sendable {
    var normalize: ([FanTarget]) throws -> [FanTarget] = { $0 }
    func normalizedTargets(_ targets: [FanTarget]) throws -> [FanTarget] { try normalize(targets) }
    var fans=[Fan(id:0,min:2000,max:8000,actual:3000,mode:.manual),Fan(id:1,min:2200,max:7400,actual:3000,mode:.manual)]
    var modeReads: [Int: Int] = [:]
    var conflictOnFinalRead = false
    var inventoryFailure=false
    var calls:[String]=[];var failAuto:Int?;var failTarget:Int?;var failManual:Int?;var now:Double=10;var hot=false;var invalid=false
    func enumerateFans() throws -> [Fan] { if inventoryFailure { throw ControlError.invalidFan };return fans }
    func fanIDsForRestoration() throws -> [Int] { fans.map(\.id) }
    func readMode(fanID:Int) throws -> FanMode {
        modeReads[fanID, default: 0] += 1
        if conflictOnFinalRead && fanID == 0 && modeReads[fanID] == 3 { fans[fanID].mode = .manual }
        return fans[fanID].mode
    }
    func setAutomatic(fanID:Int) throws { calls.append("auto\(fanID)");if failAuto==fanID { throw ControlError.invalidFan };fans[fanID].mode = .automatic }
    func setManual(fanID:Int) throws { calls.append("manual\(fanID)");if failManual==fanID { throw ControlError.invalidFan };fans[fanID].mode = .manual }
    func setTarget(fanID:Int,rpm:Double) throws { calls.append("target\(fanID)");if failTarget==fanID { throw ControlError.invalidFan };fans[fanID].targetRPM=rpm }
    func applyValidatedTargets(_ targets: [FanTarget]) throws {
        // Each fan receives its target promptly after its mode acknowledgement.
        for target in targets where fans[target.fanID].mode == .automatic {
            try setManual(fanID: target.fanID)
            guard try readMode(fanID: target.fanID) == .manual else { throw ControlError.restorationUnverified }
            try setTarget(fanID: target.fanID, rpm: target.rpm)
        }
        for target in targets where fans[target.fanID].targetRPM != target.rpm { try setTarget(fanID: target.fanID, rpm: target.rpm) }
    }
    func snapshot() -> HardwareSnapshot {
        let readings=SensorRole.allCases.map { SensorReading($0,invalid && $0 == .gpuPeak ? nil : hot ? 85 : 40,at:now,sequence:UInt64(now*10)) }
        return HardwareSnapshot(at:now,sensors:readings,fans:fans)
    }
}
@Test func restorationAttemptsEveryFanAndNeverClearsManualTarget() throws {
    let spy=FanSpy();spy.failAuto=0
    #expect(throws:(any Error).self) { try FanRestoration.restore(using:spy) }
    #expect(spy.calls == ["auto0","auto1"]);#expect(spy.fans[0].mode == .manual);#expect(spy.fans[1].mode == .automatic)
    spy.failAuto=nil;try FanRestoration.restore(using:spy);#expect(spy.fans.allSatisfy{$0.mode == .automatic})
}
@Test func failedTargetTransactionRestoresBothFans() throws {
    let spy=FanSpy();spy.failTarget=1
    #expect(throws:(any Error).self) { try FanRestoration.apply([FanTarget(0,4000),FanTarget(1,4000)],using:spy) }
    #expect(spy.fans.allSatisfy{$0.mode == .automatic})
    #expect(spy.calls.suffix(2) == ["auto0","auto1"])
}
@Test func malformedTransactionNeverBeginsHardwareWrite() {
    let spy=FanSpy()
    for targets in [[FanTarget(0,4000),FanTarget(8,4000)],[FanTarget(0,.nan),FanTarget(1,4000)],[FanTarget(0,9000),FanTarget(1,4000)],[FanTarget(0,4000),FanTarget(0,4000)]] {
        #expect(throws:(any Error).self) { try FanRestoration.apply(targets,using:spy) }
    }
    #expect(spy.calls.isEmpty)
}
func leasedCoordinator(_ spy:FanSpy) throws -> (HelperCoordinator,ControlLease,UUID) {
    let coordinator=HelperCoordinator(io:spy,capabilities: qualifiedCapabilities(),read:{spy.snapshot()},clock:{spy.now})
    #expect(coordinator.restore());for _ in 0..<5 {_ = coordinator.status()}
    let owner=UUID(),lease=try coordinator.begin(LeaseRequest(generation:1,required:SensorRole.safety),owner:owner)
    return(coordinator,lease,owner)
}
@Test func coordinatorSIGKILLEquivalentExpiresWithoutStatusRenewingHeartbeat() throws {
    let spy=FanSpy();let (coordinator,lease,owner)=try leasedCoordinator(spy)
    let snapshot=coordinator.status().snapshot!
    try coordinator.apply(TargetRequest(leaseID:lease.id,generation:1,snapshotID:snapshot.id,targets:[FanTarget(0,3000),FanTarget(1,3000)]),owner:owner)
    spy.now=19;_ = coordinator.status();coordinator.watchdog();#expect(spy.fans.allSatisfy{$0.mode == .manual})
    spy.now=20;coordinator.watchdog();#expect(spy.fans.allSatisfy{$0.mode == .automatic});#expect(coordinator.status().automaticVerified)
}
@Test func helperIndependentlyEscalatesAndSensorFailureRestores() throws {
    let spy=FanSpy();let (coordinator,lease,owner)=try leasedCoordinator(spy)
    let snapshot=coordinator.status().snapshot!
    try coordinator.apply(TargetRequest(leaseID:lease.id,generation:1,snapshotID:snapshot.id,targets:[FanTarget(0,3000),FanTarget(1,3000)]),owner:owner)
    spy.now=11;spy.hot=true;coordinator.watchdog();#expect(spy.fans.map(\.targetRPM)==[3000,3000])
    spy.now=12;spy.invalid=true;coordinator.watchdog();#expect(spy.fans.allSatisfy{$0.mode == .automatic})
}
@Test func connectionOwnerAndStaleSnapshotAreEnforced() throws {
    let spy=FanSpy();let (coordinator,lease,owner)=try leasedCoordinator(spy)
    let snapshot=coordinator.status().snapshot!
    try coordinator.apply(TargetRequest(leaseID:lease.id,generation:1,snapshotID:snapshot.id,targets:[FanTarget(0,3000),FanTarget(1,3000)]),owner:owner)
    coordinator.disconnected(owner:UUID());#expect(spy.fans.allSatisfy{$0.mode == .manual})
    #expect(throws:(any Error).self) { try coordinator.apply(TargetRequest(leaseID:lease.id,generation:1,snapshotID:UUID(),targets:[FanTarget(0,3000),FanTarget(1,3000)]),owner:owner) }
    #expect(spy.fans.allSatisfy{$0.mode == .automatic})
}
@Test func helperRestorationRetriesAndRestartDiscardsLease() throws {
    let spy=FanSpy();let (coordinator,_,_)=try leasedCoordinator(spy)
    spy.failAuto=0;#expect(!coordinator.restore());spy.failAuto=nil;coordinator.watchdog();#expect(coordinator.status().automaticVerified)
    let restarted=HelperCoordinator(io:spy,capabilities: qualifiedCapabilities(),read:{spy.snapshot()},clock:{spy.now});#expect(restarted.restore());#expect(restarted.status().automaticVerified)
}
@Test func localLogsRotateAndContainOnlyHardwareFields() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let logger=try RotatingDiagnostics(directory:directory,limit:2000),spy=FanSpy()
    for _ in 0..<8 { try logger.record(profile:"System",snapshot:spy.snapshot()) }
    #expect(try FileManager.default.contentsOfDirectory(atPath:directory.path).count <= 4)
    let text=try String(contentsOf:directory.appendingPathComponent("diagnostics.jsonl"),encoding:.utf8)
    #expect(text.contains("sensors"));#expect(!text.contains("serialNumber"))
}
@Test func restorationPreservesFreshHealthyAcquisitionsButSleepInvalidatesThem() throws {
    let spy=FanSpy();let coordinator=HelperCoordinator(io:spy,capabilities: qualifiedCapabilities(),read:{spy.snapshot()},clock:{spy.now})
    #expect(coordinator.restore());for _ in 0..<5 {_ = coordinator.status()}
    #expect(coordinator.restore())
    _ = try coordinator.begin(LeaseRequest(generation:1,required:SensorRole.safety),owner:UUID())
    coordinator.powerTransition()
    #expect(throws:(any Error).self) { _ = try coordinator.begin(LeaseRequest(generation:1,required:SensorRole.safety),owner:UUID()) }
}
@Test func reconnectCanUseFreshGenerationWithoutAcceptingOldLease() throws {
    var safety=HelperSafety();safety.restorationFinished(true);let previous=UUID(),newOwner=UUID()
    let old=try safety.begin(owner:previous,generation:100,required:SensorRole.safety,snapshot:fixture(),now:10)
    safety.revoke();safety.restorationFinished(true)
    let fresh=try safety.begin(owner:newOwner,generation:1,required:SensorRole.safety,snapshot:fixture(at:11),now:11)
    #expect(fresh.id != old.id)
    #expect(throws:(any Error).self) { try safety.validateAndRenew(owner:previous,leaseID:old.id,generation:100,targets:[],snapshot:fixture(at:11),now:11) }
}
@Test func numericOverflowAndUnknownSensorRolesRejectAtWireBoundary() {
    for json in ["{\"version\":1,\"generation\":18446744073709551616,\"required\":[]}","{\"version\":1,\"generation\":1,\"required\":[\"madeUpSensor\"]}"] {
        #expect(throws:(any Error).self) { try Wire.decode(LeaseRequest.self,from:Data(json.utf8)) }
    }
}
@Test func helperInitializationWaitsForFirstTargetAndHardwareChangesRestore() throws {
    let spy=FanSpy();let (coordinator,lease,owner)=try leasedCoordinator(spy)
    spy.now=11;coordinator.watchdog() // No target has been sent; remain automatic without revoking the lease.
    let snapshot=coordinator.status().snapshot!
    try coordinator.apply(TargetRequest(leaseID:lease.id,generation:1,snapshotID:snapshot.id,targets:[FanTarget(0,3000),FanTarget(1,3000)]),owner:owner)
    spy.fans[0].maximumRPM=7500;spy.now=12;coordinator.watchdog()
    #expect(spy.fans.allSatisfy{$0.mode == .automatic})
}

@Test func brokenRPMInventoryDoesNotPreventAutomaticRestoration() throws {
    let spy=FanSpy();spy.inventoryFailure=true
    #expect(throws:(any Error).self) { try spy.enumerateFans() }
    try FanRestoration.restore(using:spy)
    #expect(spy.fans.allSatisfy{$0.mode == .automatic})
    #expect(spy.calls == ["auto0","auto1"])
}

@Test func observationHelperNeverWritesIncludingReleasePowerAndHostileRequests() throws {
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: HardwareCapabilities(model: "Test"), read: {
        var snapshot = spy.snapshot()
        snapshot.sensors = snapshot.sensors.map { reading in var value = reading; value.health = .unverified; return value }
        return snapshot
    }, clock: { spy.now })
    let status = coordinator.status()
    #expect(status.observationOnly); #expect(!status.manualQualified); #expect(!status.automaticVerified)
    #expect(status.snapshot?.fans.count == 2)
    #expect(throws: ControlError.hardwareUnqualified) { _ = try coordinator.begin(LeaseRequest(generation: 1, required: []), owner: UUID()) }
    #expect(throws: (any Error).self) {
        try coordinator.apply(TargetRequest(leaseID: UUID(), generation: 1, snapshotID: UUID(), targets: [FanTarget(0, 4000)]), owner: UUID())
    }
    #expect(!coordinator.restore())
    coordinator.powerTransition(); coordinator.watchdog(); coordinator.disconnected(owner: UUID()); coordinator.reject(owner: UUID())
    #expect(spy.calls.isEmpty); #expect(spy.fans.allSatisfy { $0.mode == .manual })
}

@Test func observationOwnershipUsesFreshFanEvidenceAndNeverCachesSystemOnReadFailure() throws {
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: HardwareCapabilities(model: "Test"), read: {
        if spy.inventoryFailure { throw ControlError.invalidFan }
        return spy.snapshot()
    }, clock: { spy.now })
    #expect(!coordinator.status().automaticVerified)
    spy.fans[0].mode = .automatic; spy.fans[1].mode = .automatic
    #expect(coordinator.status().automaticVerified)
    spy.inventoryFailure = true
    let status = coordinator.status()
    #expect(!status.automaticVerified); #expect(status.snapshot == nil); #expect(status.fault != nil)
    #expect(spy.calls.isEmpty)
}

@Test func observationRejectsStaleAndInvalidFanSnapshots() {
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: HardwareCapabilities(model: "Test"), read: { spy.snapshot() }, clock: { spy.now + 4 })
    #expect(!coordinator.status().automaticVerified); #expect(coordinator.status().snapshot == nil)
    #expect(spy.calls.isEmpty)
}

@Test func failedControlStatusCannotReportPreviousAutomaticVerification() {
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: {
        if spy.inventoryFailure { throw ControlError.invalidFan }
        return spy.snapshot()
    }, clock: { spy.now })
    #expect(coordinator.restore()); #expect(coordinator.status().automaticVerified)
    spy.inventoryFailure = true
    #expect(!coordinator.status().automaticVerified)
}

func qualifiedCapabilities(stage: HardwareStage = .qualifiedControl) -> HardwareCapabilities {
    HardwareCapabilities(model: "Test", stage: stage,
        sensors: HardwareCapabilities.requiredRoles.map { SensorEvidence(role: $0, keys: ["TEST"], state: .verified, source: "Injected test evidence", limitation: "Not hardware qualification") },
        topology: .verified, automaticRestoration: .verified, manualTransaction: .verified)
}

@Test func normalizedAcknowledgementsAndIndependentGuardUseTheSamePhysicalTargets() throws {
    let spy = FanSpy(); spy.normalize = { $0.map { FanTarget($0.fanID, ceil($0.rpm)) } }
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: {
        var snapshot = spy.snapshot()
        if spy.hot { for i in snapshot.sensors.indices { snapshot.sensors[i].celsius = 78.2 } }
        return snapshot
    }, clock: { spy.now })
    #expect(coordinator.startup()); for _ in 0..<5 { _ = coordinator.status() }
    let owner = UUID(), lease = try coordinator.begin(LeaseRequest(generation: 1, required: SensorRole.safety), owner: owner)
    let snapshot = coordinator.status().snapshot!
    try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id, targets: [FanTarget(0, 3000.2), FanTarget(1, 3000.7)]), owner: owner)
    #expect(coordinator.status().fault == nil)
    #expect(spy.fans.allSatisfy { $0.targetRPM == 3001 })
    spy.hot = true; spy.now += 1; coordinator.watchdog()
    #expect(coordinator.status().fault == nil)
    #expect(spy.fans.allSatisfy { $0.targetRPM == 3001 })
    spy.normalize = { $0.map { FanTarget($0.fanID, $0.rpm - 1) } }
    let fresh = coordinator.status().snapshot!
    #expect(throws: ControlError.invalidFan) { try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: fresh.id, targets: [FanTarget(0, 3000.2), FanTarget(1, 3000.7)]), owner: owner) }
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}
